# frozen_string_literal: true

module EbookReader
  module Services
    class BookmarkService
      def initialize(reader)
        @reader = reader
      end

      def add_bookmark
        line_offset = @reader.config.view_mode == :split ? @reader.left_page : @reader.single_page
        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        text_snippet = @reader.send(:extract_bookmark_text, chapter, line_offset)
        data = Models::BookmarkData.new(
          path: @reader.path,
          chapter: @reader.current_chapter,
          line_offset: line_offset,
          text: text_snippet
        )
        BookmarkManager.add(data)
        @reader.send(:load_bookmarks)
        @reader.send(:set_message, Constants::Messages::BOOKMARK_ADDED)
      end
    end
  end
end
