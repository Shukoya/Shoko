# frozen_string_literal: true

module EbookReader
  module Services
    class NavigationService
      def initialize(reader)
        @reader = reader
      end

      def next_page_absolute
        height, width = Terminal.size
        col_width, content_height = @reader.send(:get_layout_metrics, width, height)
        content_height = @reader.send(:adjust_for_line_spacing, content_height)

        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        wrapped = @reader.wrap_lines(chapter.lines || [], col_width)
        max_page = [wrapped.size - content_height, 0].max

        if @reader.config.view_mode == :split
          @reader.send(:handle_split_next_page, max_page, content_height)
        else
          @reader.send(:handle_single_next_page, max_page, content_height)
        end
      end

      def go_to_end
        height, width = Terminal.size
        col_width, content_height = @reader.send(:get_layout_metrics, width, height)
        content_height = @reader.send(:adjust_for_line_spacing, content_height)

        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        wrapped = @reader.wrap_lines(chapter.lines || [], col_width)
        max_page = [wrapped.size - content_height, 0].max

        if @reader.config.view_mode == :split
          @reader.right_page = max_page
          @reader.left_page = [max_page - content_height, 0].max
        else
          @reader.single_page = max_page
        end
      end

      def next_chapter
        if @reader.config.page_numbering_mode == :dynamic
          return unless @reader.current_chapter < @reader.doc.chapter_count - 1

          target_page_index = @reader.page_manager.pages_data.find_index do |page|
            page[:chapter_index] == @reader.current_chapter + 1
          end

          if target_page_index
            @reader.current_page_index = target_page_index
            @reader.current_chapter += 1
          end
        else
          @reader.current_chapter += 1
          @reader.send(:reset_pages)
          @reader.send(:save_progress)
        end
      end

      def prev_chapter
        if @reader.config.page_numbering_mode == :dynamic
          return unless @reader.current_chapter.positive?

          target_page_index = @reader.page_manager.pages_data.find_index do |page|
            page[:chapter_index] == @reader.current_chapter - 1
          end

          if target_page_index
            @reader.current_page_index = target_page_index
            @reader.current_chapter -= 1
          end
        else
          @reader.current_chapter -= 1
          @reader.send(:reset_pages)
        end
      end
    end
  end
end
