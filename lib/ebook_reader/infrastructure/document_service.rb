# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Document service for loading and accessing EPUB content.
    # Provides clean interface to document operations without coupling to controllers.
    class DocumentService
      def initialize(epub_path, wrapping_service = nil)
        @epub_path = epub_path
        @document = nil
        @content_cache = {}
        @wrapping_service = wrapping_service
      end

      # Load the EPUB document
      #
      # @return [EPUBDocument] Loaded document
      def load_document
        @document ||= EPUBDocument.new(@epub_path)
      rescue StandardError => e
        Infrastructure::Logger.error('Failed to load document', path: @epub_path, error: e.message)
        create_error_document(e.message)
      end

      # Get chapter by index
      #
      # @param index [Integer] Chapter index
      # @return [Chapter] Chapter object or nil
      def get_chapter(index)
        return nil unless @document

        @document.get_chapter(index)
      end

      # Get table of contents
      #
      # @return [Array<Hash>] Array of TOC entries
      def get_table_of_contents
        return [] unless @document

        @document.chapters.map.with_index do |chapter, index|
          {
            index: index,
            title: chapter.title || "Chapter #{index + 1}",
            level: 0, # Could be enhanced to support nested TOC
          }
        end
      end

      # Get content for specific page
      #
      # @param chapter_index [Integer] Chapter index
      # @param page_offset [Integer] Page offset within chapter
      # @param lines_per_page [Integer] Number of lines per page
      # @return [Array<String>] Array of content lines
      def get_page_content(chapter_index, page_offset, lines_per_page = 20)
        cache_key = "#{chapter_index}_#{page_offset}_#{lines_per_page}"

        return @content_cache[cache_key] if @content_cache.key?(cache_key)

        chapter = get_chapter(chapter_index)
        return [] unless chapter

        lines = chapter.lines || []
        start_line = page_offset * lines_per_page
        end_line = start_line + lines_per_page - 1

        content = lines[start_line..end_line] || []
        @content_cache[cache_key] = content

        content
      end

      # Get wrapped content for specific page
      #
      # @param chapter_index [Integer] Chapter index
      # @param page_offset [Integer] Page offset within chapter
      # @param column_width [Integer] Column width for wrapping
      # @param lines_per_page [Integer] Number of lines per page
      # @return [Array<String>] Array of wrapped content lines
      def get_wrapped_page_content(chapter_index, page_offset, column_width, lines_per_page = 20)
        cache_key = "wrapped_#{chapter_index}_#{page_offset}_#{column_width}_#{lines_per_page}"

        return @content_cache[cache_key] if @content_cache.key?(cache_key)

        chapter = get_chapter(chapter_index)
        return [] unless chapter

        lines = chapter.lines || []
        wrapped_lines = wrap_lines(lines, column_width)

        start_line = page_offset * lines_per_page
        end_line = start_line + lines_per_page - 1

        content = wrapped_lines[start_line..end_line] || []
        @content_cache[cache_key] = content

        content
      end

      # Get total wrapped lines for chapter
      #
      # @param chapter_index [Integer] Chapter index
      # @param column_width [Integer] Column width for wrapping
      # @return [Integer] Total wrapped lines
      def get_chapter_wrapped_line_count(chapter_index, column_width)
        cache_key = "line_count_#{chapter_index}_#{column_width}"

        return @content_cache[cache_key] if @content_cache.key?(cache_key)

        chapter = get_chapter(chapter_index)
        return 0 unless chapter

        lines = chapter.lines || []
        wrapped_lines = wrap_lines(lines, column_width)

        count = wrapped_lines.size
        @content_cache[cache_key] = count

        count
      end

      # Clear content cache
      def clear_cache
        @content_cache.clear
      end

      # Clear cache for specific width
      #
      # @param width [Integer] Column width
      def clear_cache_for_width(width)
        @content_cache.delete_if { |key, _| key.include?("_#{width}_") }
      end

      private

      def create_error_document(error_message)
        # Create a simple document with error information
        ErrorDocument.new(error_message)
      end

      def wrap_lines(lines, column_width)
        return lines if column_width <= 0
        return @wrapping_service.wrap_lines(lines, 0, column_width) if @wrapping_service

        # Minimal fallback for tests/dev without DI
        lines
      end
    end

    # Simple error document for when EPUB loading fails
    class ErrorDocument
      attr_reader :error_message

      def initialize(error_message)
        @error_message = error_message
      end

      def chapter_count
        1
      end

      def get_chapter(index)
        return nil unless index.zero?

        ErrorChapter.new(@error_message)
      end

      def chapters
        [get_chapter(0)]
      end
    end

    # Simple error chapter
    class ErrorChapter
      attr_reader :title, :lines

      def initialize(error_message)
        @title = 'Error Loading Book'
        @lines = [
          'Failed to load the EPUB file:',
          '',
          error_message,
          '',
          'Please check that the file exists and is a valid EPUB.',
          '',
          "Press 'q' to return to the main menu.",
        ]
      end
    end
  end
end
