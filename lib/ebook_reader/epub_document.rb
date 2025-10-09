# frozen_string_literal: true

require_relative 'infrastructure/logger'
require_relative 'infrastructure/performance_monitor'
require_relative 'infrastructure/perf_tracer'

require 'zip'
require 'rexml/document'
require_relative 'helpers/html_processor'
require_relative 'helpers/opf_processor'
require_relative 'domain/models/chapter'
require_relative 'domain/models/toc_entry'
require 'json'
require 'fileutils'
require 'pathname'
require_relative 'infrastructure/epub_cache'

module EbookReader
  # EPUB document class
  class EPUBDocument
    attr_reader :title, :chapters, :language, :source_path, :cache_dir, :toc_entries

    ChapterRef = Struct.new(:file_path, :number, :title, :href, keyword_init: true)

    def initialize(path, formatting_service: nil, background_worker: nil)
      @path = path
      @title = File.basename(path, '.epub').tr('_', ' ')
      @language = 'en_US'
      @chapters = []
      @zip = nil
      @cache_dir = nil
      @opf_path = nil
      @spine_relative_paths = []
      @authors = []
      @loaded_from_cache = false
      @source_path = @path
      @formatting_service = formatting_service
      @toc_entries = []
      @background_worker = background_worker

      # Try to use cache first; fall back to parsing the EPUB
      # Allow opening directly from a cache directory (Library open)
      if Infrastructure::PerfTracer.measure('cache.lookup') { load_from_cache_dir(@path) }
        Infrastructure::Logger.debug('Loaded EPUB from cache dir', dir: @path)
      elsif Infrastructure::PerfTracer.measure('cache.lookup') { load_from_cache }
        Infrastructure::Logger.debug('Loaded EPUB from cache', path: @path)
      else
        @zip = Infrastructure::PerfTracer.measure('zip.read') { Zip::File.open(@path) }
        parse_epub
        # Populate cache in the background to keep first open responsive
        schedule_cache_population
      end
      rebuild_toc_entries! if @toc_entries.empty?
    rescue StandardError => e
      create_error_chapter(e)
    end

    def chapter_count
      @chapters.size
    end

    def get_chapter(index)
      return nil if @chapters.empty?

      return nil unless index >= 0 && index < @chapters.size

      entry = @chapters[index]

      return entry if entry.is_a?(Domain::Models::Chapter)

      chapter = load_chapter(entry)
      @chapters[index] = chapter if chapter
      chapter
    end

    def cached?
      @loaded_from_cache
    end

    # Canonical source path for persistence (always the original .epub path when known)
    # Falls back to the provided path when opening a raw EPUB without cache.
    def canonical_path
      @source_path || @path
    end

    private

    # Parse the EPUB file and populate chapter references.
    #
    # The EPUB archive is read directly without extracting files to disk.
    # We locate the OPF file described in META-INF/container.xml and use
    # it to build a list of chapters. Any errors encountered during this
    # process are captured and presented to the user as a single "Error"
    # chapter so the application can continue running.
    def parse_epub
      Infrastructure::Logger.info('Parsing EPUB', path: @path)
      Infrastructure::PerformanceMonitor.time('import.parse_epub') do
        Infrastructure::PerformanceMonitor.time('epub_parsing') do
          opf_path = find_opf_path
          @opf_path = opf_path if opf_path
          process_opf(opf_path) if opf_path
          ensure_chapters_exist
        end
      end
    rescue StandardError => e
      create_error_chapter(e)
    end

    def create_error_chapter(error)
      @chapters = [
        Domain::Models::Chapter.new(
          number: '1',
          title: 'Error Loading',
          lines: ["Error: #{error.message}"],
          metadata: nil,
          blocks: nil,
          raw_content: nil
        ),
      ]
      @toc_entries = []
    end

    # Locate the OPF package file which describes the contents of the
    # EPUB. Its path is defined in META-INF/container.xml as required by
    # the EPUB specification.
    def find_opf_path
      container_xml = Infrastructure::PerfTracer.measure('zip.read') { @zip.read('META-INF/container.xml') }
      begin
        container = REXML::Document.new(container_xml)
        elems = container.elements
        rootfile = elems['//rootfile'] || elems['//container:rootfile']
        if rootfile
          opf_path = rootfile.attributes['full-path']
          return opf_path if opf_path && @zip.find_entry(opf_path)
        end
      rescue StandardError
        # fall through to regex fallback
      end

      # Fallback: extract via regex in case of namespace quirks
      if (m = container_xml.to_s.match(/full-path=["']([^"']+)["']/i))
        path = m[1]
        return path if @zip.find_entry(path)
      end
      nil
    end

    # Parse the OPF file using the helper processor. This extracts
    # metadata such as the book title and language, builds a manifest of
    # all items in the EPUB, and walks the spine to determine chapter
    # order. Instead of reading chapter files immediately we store
    # references so that content can be loaded lazily.
    def process_opf(opf_path)
      processor = Helpers::OPFProcessor.new(opf_path, zip: @zip)

      # Extract metadata
      metadata = processor.extract_metadata
      @title = metadata[:title] || @title
      @language = metadata[:language] || @language
      @authors = Array(metadata[:authors]).compact

      # Build manifest and get chapter titles
      manifest = processor.build_manifest_map
      chapter_titles = processor.extract_chapter_titles(manifest)

      # Process spine without loading chapter content
      @spine_relative_paths = []
      processor.process_spine(manifest, chapter_titles) do |file_path, number, title, href|
        @chapters << ChapterRef.new(file_path:, number:, title:, href: resolve_href_reference(href))
        @spine_relative_paths << file_path
      end
      assign_toc_entries(processor.toc_entries)
    end

    def ensure_chapters_exist
      return unless @chapters.empty?

      @chapters << Domain::Models::Chapter.new(
        number: '1',
        title: 'Empty Book',
        lines: ['This EPUB appears to be empty.'],
        metadata: nil,
        blocks: nil,
        raw_content: nil
      )
      @toc_entries = []
    end

    # Load a single chapter HTML file and convert it to plain text lines.
    # If an error occurs while reading or parsing the file we simply skip the
    # chapter so the rest of the book can still be viewed. Titles are
    # extracted from the HTML when available or generated automatically.
    def load_chapter(entry)
      fp = entry.file_path
      content = if @zip
                  read_entry_content(@zip, fp)
                else
                  read_file_content(fp)
                end
      create_chapter_from_content(content, entry.number, entry.title)
    rescue Errno::ENOENT, Zip::Error, REXML::ParseException
      nil
    end

    def close
      @zip.close if @zip && !@zip.closed?
    end

    def create_chapter_from_content(content, number, title_from_ncx)
      title = extract_chapter_title(content, number, title_from_ncx)
      chapter = Domain::Models::Chapter.new(
        number: number.to_s,
        title: title,
        lines: nil,
        metadata: nil,
        blocks: nil,
        raw_content: content
      )
      ensure_formatted_chapter(chapter, number)
      chapter.lines ||= fallback_plain_lines(content)
      chapter
    end

    def extract_chapter_title(content, number, title_from_ncx)
      title_from_ncx || Helpers::HTMLProcessor.extract_title(content) || "Chapter #{number}"
    end

    def ensure_formatted_chapter(chapter, number)
      return unless @formatting_service && chapter

      chapter_index = number.to_i - 1
      chapter_index = 0 if chapter_index.negative?
      begin
        @formatting_service.ensure_formatted!(self, chapter_index, chapter)
      rescue EbookReader::FormattingError => e
        Infrastructure::Logger.error('Formatting error', error: e.message, chapter: number)
        raise
      rescue StandardError
        # Fallback handled by caller
      end
    end

    def fallback_plain_lines(content)
      text = Helpers::HTMLProcessor.html_to_text(content)
      text.split("\n").map(&:rstrip)
    end

    def assign_toc_entries(entries)
      raw_entries = entries || []
      href_to_index = {}
      @chapters.each_with_index do |ref, idx|
        next unless ref&.href

        href_to_index[ref.href] = idx
      end

      @toc_entries = raw_entries.map do |entry|
        level = entry[:level].to_i
        href = entry[:href]
        resolved = resolve_href_reference(href)
        chapter_index = href_to_index[resolved]
        if chapter_index && (ref = @chapters[chapter_index]) && ref.respond_to?(:title=)
          ref.title = entry[:title]
        end
        Domain::Models::TOCEntry.new(
          title: entry[:title],
          href: href,
          level: level,
          chapter_index: chapter_index,
          navigable: !chapter_index.nil?
        )
      end
    end

    def rebuild_toc_entries!
      return unless @opf_path

      zip = nil
      processor = nil
      if File.file?(@path)
        zip = Infrastructure::PerfTracer.measure('zip.read') { Zip::File.open(@path) }
        processor = Helpers::OPFProcessor.new(@opf_path, zip: zip)
      else
        base_dir = @cache_dir || File.dirname(@path)
        processor = Helpers::OPFProcessor.new(File.join(base_dir, @opf_path))
      end
      manifest = processor.build_manifest_map
      chapter_titles = processor.extract_chapter_titles(manifest)
      processor.process_spine(manifest, chapter_titles) do |file_path, number, title, _href|
        index = number - 1
        if (ref = @chapters[index])
          ref.file_path ||= file_path if ref.respond_to?(:file_path=)
          ref.title = title if ref.respond_to?(:title=)
        end
      end
      assign_toc_entries(processor.toc_entries)
    rescue StandardError
      @toc_entries ||= []
    ensure
      zip&.close
    end

    def resolve_href_reference(href, include_anchor: false)
      return nil unless href

      base = @opf_path ? File.dirname(@opf_path) : '.'
      core, anchor = href.split('#', 2)
      cleaned = File.expand_path(File.join('/', base, core), '/')
      cleaned.sub!(%r{^/}, '')
      return cleaned unless include_anchor && anchor

      "#{cleaned}##{anchor}"
    end

    def load_cached_toc_entries
      return [] unless @opf_path && @cache_dir

      opf_full_path = File.join(@cache_dir, @opf_path)
      return [] unless File.exist?(opf_full_path)

      processor = Helpers::OPFProcessor.new(opf_full_path)
      manifest = processor.build_manifest_map
      processor.extract_chapter_titles(manifest)
      processor.toc_entries
    rescue StandardError
      []
    end

    # Utility method to read a file as UTF-8 while stripping any UTF-8
    # BOM that may be present.
    def read_entry_content(zip, path)
      content = Infrastructure::PerfTracer.measure('zip.read') { zip.read(path) }
      content.force_encoding('UTF-8')
      content = content[1..] if content.start_with?("\uFEFF")
      content
    end

    def read_file_content(path)
      content = File.binread(path)
      content.force_encoding('UTF-8')
      content = content[1..] if content.start_with?("\uFEFF")
      content
    end

    # ---------------------------
    # Cache support (delegates to Infrastructure::EpubCache)
    # ---------------------------
    def load_from_cache
      Infrastructure::PerformanceMonitor.time('import.cache.load') do
        cache = Infrastructure::EpubCache.new(@path)
        manifest = cache.load_manifest
        return false unless manifest&.spine&.any?

        m = manifest
        title_str = m.title.to_s
        @title = title_str unless title_str.empty?
        @opf_path = m.opf_path
        @spine_relative_paths = m.spine
        @cache_dir = cache.cache_dir
        epub_path_str = m.epub_path.to_s
        @source_path = epub_path_str unless epub_path_str.empty?

        # Validate cached files exist and remain within cache root
        container_path = cache_abs(cache, 'META-INF/container.xml')
        return false unless container_path && File.exist?(container_path)

        opf_path = cache_abs(cache, @opf_path)
        return false unless opf_path && File.exist?(opf_path)

        abs_paths = @spine_relative_paths.map { |rel| cache_abs(cache, rel) }
        return false unless abs_paths.all? { |p| p && File.exist?(p) }

        # Build chapter refs pointing to cached files
        @chapters = []
        abs_paths.each_with_index do |abs, idx|
          rel = @spine_relative_paths[idx]
          next unless abs

          @chapters << ChapterRef.new(file_path: abs, number: idx + 1, title: nil,
                                      href: resolve_href_reference(rel))
        end
        @loaded_from_cache = true
        assign_toc_entries(load_cached_toc_entries)
        true
      end
    end

    def load_from_cache_dir(dir)
      Infrastructure::PerformanceMonitor.time('import.cache_dir.load') do
        return false unless File.directory?(dir)

        mp = File.join(dir, 'manifest.msgpack')
        js = File.join(dir, 'manifest.json')
        serializer = nil
        manifest_path = nil
        if File.exist?(mp)
          begin
            require 'msgpack'
            serializer = EbookReader::Infrastructure::MessagePackSerializer.new
            manifest_path = mp
          rescue LoadError
            # fallback to json if present
          end
        end
        if manifest_path.nil? && File.exist?(js)
          serializer = EbookReader::Infrastructure::JSONSerializer.new
          manifest_path = js
        end
        return false unless serializer && manifest_path

        data = serializer.load_file(manifest_path)
        spine_val = hget(data, :spine)
        return false unless data.is_a?(Hash) && spine_val.is_a?(Array)

        @cache_dir = dir
        title_v = hget(data, :title)
        @title = title_v.to_s if title_v
        @opf_path = s(hget(data, :opf_path))
        @spine_relative_paths = (spine_val || []).map(&:to_s)
        epub_path_v = s(hget(data, :epub_path))
        @source_path = epub_path_v unless epub_path_v.empty?

        sanitize = lambda do |rel|
          cleaned = Pathname.new(rel.to_s).cleanpath.to_s
          next nil if cleaned.empty?

          dest = File.expand_path(cleaned, @cache_dir)
          prefix = @cache_dir.end_with?(File::SEPARATOR) ? @cache_dir : (@cache_dir + File::SEPARATOR)
          next dest if dest.start_with?(prefix) || dest == @cache_dir

          nil
        end

        container_path = sanitize.call(File.join('META-INF', 'container.xml'))
        return false unless container_path && File.exist?(container_path)

        opf_path = sanitize.call(@opf_path)
        return false unless opf_path && File.exist?(opf_path)

        @chapters = []
        @spine_relative_paths.each_with_index do |rel, idx|
          abs = sanitize.call(rel)
          return false unless abs && File.exist?(abs)

          @chapters << ChapterRef.new(file_path: abs, number: idx + 1, title: nil,
                                      href: resolve_href_reference(rel))
        end
        @loaded_from_cache = true
        assign_toc_entries(load_cached_toc_entries)
        true
      end
    rescue StandardError
      false
    end

    def safely_build_cache
      build_cache
    rescue StandardError => e
      Infrastructure::Logger.debug('Failed to build cache', error: e.message)
    end

    def build_cache
      return unless @opf_path && !@spine_relative_paths.empty?

      Infrastructure::PerformanceMonitor.time('import.cache.populate') do
        cache = Infrastructure::EpubCache.new(@path)
        Zip::File.open(@path) do |zip|
          cache.populate!(zip, @opf_path, @spine_relative_paths)
        end
        authors = Array(@authors).compact.map(&:to_s)
        manifest = Infrastructure::EpubCache::Manifest.new(
          title: @title,
          author_str: authors.join(', '),
          authors: authors,
          opf_path: @opf_path,
          spine: @spine_relative_paths,
          epub_path: @path
        )
        cache.write_manifest!(manifest)
        @cache_dir = cache.cache_dir
      end
    end

    def schedule_cache_population
      if @background_worker
        @background_worker.submit { safely_build_cache }
      else
        Thread.new { safely_build_cache }
      end
    rescue StandardError => e
      Infrastructure::Logger.debug('Background cache thread failed', error: e.message)
      Thread.new { safely_build_cache }
    end
  end
end

module EbookReader
  class EPUBDocument
    private

    # Indifferent hash access (symbol/string)
    def hget(h, key)
      h[key] || h[key.to_s]
    end

    # Safe string
    def s(val)
      val.to_s
    end

    # Cache absolute path helper
    def cache_abs(cache, rel)
      cache.cache_abs_path(rel)
    end
  end
end
