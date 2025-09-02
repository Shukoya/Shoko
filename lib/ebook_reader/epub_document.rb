# frozen_string_literal: true

require_relative 'infrastructure/logger'
require_relative 'infrastructure/performance_monitor'

require 'zip'
require 'rexml/document'
require_relative 'helpers/html_processor'
require_relative 'helpers/opf_processor'
require_relative 'domain/models/chapter'

module EbookReader
  # EPUB document class
  class EPUBDocument
    attr_reader :title, :chapters, :language

    ChapterRef = Struct.new(:file_path, :number, :title, keyword_init: true)

    def initialize(path)
      @path = path
      @title = File.basename(path, '.epub').tr('_', ' ')
      @language = 'en_US'
      @chapters = []
      @zip = Zip::File.open(@path)
      parse_epub
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
      container = REXML::Document.new(container_xml)
      rootfile = container.elements['//rootfile']
      return unless rootfile

      opf_path = rootfile.attributes['full-path']
      opf_path if @zip.find_entry(opf_path)
    rescue StandardError
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

      # Build manifest and get chapter titles
      manifest = processor.build_manifest_map
      chapter_titles = processor.extract_chapter_titles(manifest)

      # Process spine without loading chapter content
      processor.process_spine(manifest, chapter_titles) do |file_path, number, title|
        @chapters << ChapterRef.new(file_path:, number:, title:)
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
      content = read_entry_content(@zip, entry.file_path)
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
  end
end
