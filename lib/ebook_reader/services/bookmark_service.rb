# frozen_string_literal: true

module EbookReader
  module Services
    class BookmarkService
      def initialize(reader)
        @reader = reader
      end

      def add_bookmark
        bookmark_data = create_bookmark_data
        return unless bookmark_data

        persist_bookmark(bookmark_data)
        notify_bookmark_added
      end

      private

      def create_bookmark_data
        line_offset = current_line_offset
        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        text_snippet = @reader.send(:extract_bookmark_text, chapter, line_offset)

        Models::BookmarkData.new(
          path: @reader.path,
          chapter: @reader.current_chapter,
          line_offset: line_offset,
          text: text_snippet
        )
      end

      def current_line_offset
        @reader.config.view_mode == :split ? @reader.left_page : @reader.single_page
      end

      def persist_bookmark(bookmark_data)
        BookmarkManager.add(bookmark_data)
        @reader.send(:load_bookmarks)
      end

      def notify_bookmark_added
        @reader.send(:set_message, Constants::Messages::BOOKMARK_ADDED)
      end
    end
  end
end
