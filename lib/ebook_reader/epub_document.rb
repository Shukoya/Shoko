# frozen_string_literal: true

require_relative 'infrastructure/logger'
require_relative 'infrastructure/performance_monitor'

require 'zip'
require 'rexml/document'
require_relative 'helpers/html_processor'
require_relative 'helpers/opf_processor'
require_relative 'domain/models/chapter'
require 'json'
require 'fileutils'
require_relative 'infrastructure/epub_cache'

module EbookReader
  # EPUB document class
  class EPUBDocument
    attr_reader :title, :chapters, :language, :source_path, :cache_dir

    ChapterRef = Struct.new(:file_path, :number, :title, keyword_init: true)

    def initialize(path)
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

      # Try to use cache first; fall back to parsing the EPUB
      # Allow opening directly from a cache directory (Library open)
      if load_from_cache_dir(@path)
        Infrastructure::Logger.debug('Loaded EPUB from cache dir', dir: @path)
      elsif load_from_cache
        Infrastructure::Logger.debug('Loaded EPUB from cache', path: @path)
      else
        @zip = Zip::File.open(@path)
        parse_epub
        # Populate cache in the background to keep first open responsive
        begin
          Thread.new { safely_build_cache }
        rescue StandardError => e
          Infrastructure::Logger.debug('Background cache thread failed', error: e.message)
        end
      end
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
      Infrastructure::PerformanceMonitor.time('epub_parsing') do
        opf_path = find_opf_path
        @opf_path = opf_path if opf_path
        process_opf(opf_path) if opf_path
        ensure_chapters_exist
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
          metadata: nil
        ),
      ]
    end

    # Locate the OPF package file which describes the contents of the
    # EPUB. Its path is defined in META-INF/container.xml as required by
    # the EPUB specification.
    def find_opf_path
      container_xml = @zip.read('META-INF/container.xml')
      begin
        container = REXML::Document.new(container_xml)
        rootfile = container.elements['//rootfile'] || container.elements['//container:rootfile']
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
      processor.process_spine(manifest, chapter_titles) do |file_path, number, title|
        @chapters << ChapterRef.new(file_path:, number:, title:)
        @spine_relative_paths << file_path
      end
    end

    def ensure_chapters_exist
      return unless @chapters.empty?

      @chapters << Domain::Models::Chapter.new(
        number: '1',
        title: 'Empty Book',
        lines: ['This EPUB appears to be empty.'],
        metadata: nil
      )
    end

    # Load a single chapter HTML file and convert it to plain text lines.
    # If an error occurs while reading or parsing the file we simply skip the
    # chapter so the rest of the book can still be viewed. Titles are
    # extracted from the HTML when available or generated automatically.
    def load_chapter(entry)
      content = if @zip
                  read_entry_content(@zip, entry.file_path)
                else
                  read_file_content(entry.file_path)
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
      lines = extract_chapter_lines(content)

      Domain::Models::Chapter.new(
        number: number.to_s,
        title: title,
        lines: lines,
        metadata: nil
      )
    end

    def extract_chapter_title(content, number, title_from_ncx)
      title_from_ncx || Helpers::HTMLProcessor.extract_title(content) || "Chapter #{number}"
    end

    def extract_chapter_lines(content)
      text = Helpers::HTMLProcessor.html_to_text(content)
      text.split("\n").reject { |line| line.strip.empty? }
    end

    # Utility method to read a file as UTF-8 while stripping any UTF-8
    # BOM that may be present.
    def read_entry_content(zip, path)
      content = zip.read(path)
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
      cache = Infrastructure::EpubCache.new(@path)
      manifest = cache.load_manifest
      return false unless manifest&.spine&.any?

      @title = manifest.title unless manifest.title.to_s.empty?
      @opf_path = manifest.opf_path
      @spine_relative_paths = manifest.spine
      @cache_dir = cache.cache_dir
      @source_path = manifest.epub_path.to_s unless manifest.epub_path.to_s.empty?

      # Validate cached files exist
      return false unless File.exist?(cache.cache_abs_path('META-INF/container.xml'))
      return false unless File.exist?(cache.cache_abs_path(@opf_path))
      return false unless @spine_relative_paths.all? do |rel|
        File.exist?(cache.cache_abs_path(rel))
      end

      # Build chapter refs pointing to cached files
      @chapters = []
      @spine_relative_paths.each_with_index do |rel, idx|
        abs = cache.cache_abs_path(rel)
        @chapters << ChapterRef.new(file_path: abs, number: idx + 1, title: nil)
      end
      @loaded_from_cache = true
      true
    end

    def load_from_cache_dir(dir)
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
      return false unless data.is_a?(Hash) && data['spine'].is_a?(Array)

      @cache_dir = dir
      @title = data['title'].to_s if data['title']
      @opf_path = data['opf_path'].to_s
      @spine_relative_paths = data['spine'].map(&:to_s)
      @source_path = data['epub_path'].to_s unless data['epub_path'].to_s.empty?

      return false unless File.exist?(File.join(@cache_dir, 'META-INF', 'container.xml'))
      return false unless File.exist?(File.join(@cache_dir, @opf_path))

      @chapters = []
      @spine_relative_paths.each_with_index do |rel, idx|
        abs = File.join(@cache_dir, rel)
        @chapters << ChapterRef.new(file_path: abs, number: idx + 1, title: nil)
      end
      @loaded_from_cache = true
      true
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
end
