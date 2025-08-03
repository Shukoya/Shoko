# frozen_string_literal: true

module EbookReader
  module Services
    class NavigationService
      def initialize(reader)
        @reader = reader
      end

      def next_page_absolute
        metrics = calculate_page_metrics
        return unless metrics[:chapter]

        navigate_to_next_page(metrics)
      end

      private

      def calculate_page_metrics
        height, width = Terminal.size
        col_width, content_height = @reader.send(:get_layout_metrics, width, height)
        content_height = @reader.send(:adjust_for_line_spacing, content_height)
        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return {} unless chapter

        max_page = compute_max_page(chapter, col_width, content_height)
        { chapter: chapter, content_height: content_height, max_page: max_page }
      end

      def compute_max_page(chapter, col_width, content_height)
        wrapped = @reader.wrap_lines(chapter.lines || [], col_width)
        [wrapped.size - content_height, 0].max
      end

      def navigate_to_next_page(metrics)
        if @reader.config.view_mode == :split
          @reader.send(:handle_split_next_page, metrics[:max_page], metrics[:content_height])
        else
          @reader.send(:handle_single_next_page, metrics[:max_page], metrics[:content_height])
        end
      end

      def go_to_end
        metrics = calculate_page_metrics
        return unless metrics[:chapter]

        position_at_end(metrics[:max_page], metrics[:content_height])
      end

      def position_at_end(max_page, content_height)
        if @reader.config.view_mode == :split
          position_split_view_at_end(max_page, content_height)
        else
          position_single_view_at_end(max_page)
        end
      end

      def position_split_view_at_end(max_page, content_height)
        @reader.right_page = max_page
        @reader.left_page = [max_page - content_height, 0].max
      end

      def position_single_view_at_end(max_page)
        @reader.single_page = max_page
      end

      def next_chapter
        if @reader.config.page_numbering_mode == :dynamic
          next_chapter_dynamic
        else
          next_chapter_absolute
        end
      end

      def next_chapter_dynamic
        return unless can_go_to_next_chapter?

        target_page_index = find_chapter_start_page(@reader.current_chapter + 1)
        if target_page_index
          @reader.current_page_index = target_page_index
          @reader.current_chapter += 1
        end
      end

      def next_chapter_absolute
        @reader.current_chapter += 1
        @reader.send(:reset_pages)
        @reader.send(:save_progress)
      end

      def can_go_to_next_chapter?
        @reader.current_chapter < @reader.doc.chapter_count - 1
      end

      def find_chapter_start_page(chapter_index)
        @reader.page_manager.pages_data.find_index do |page|
          page[:chapter_index] == chapter_index
        end
      end

      def prev_chapter
        if @reader.config.page_numbering_mode == :dynamic
          prev_chapter_dynamic
        else
          prev_chapter_absolute
        end
      end

      def prev_chapter_dynamic
        return unless can_go_to_prev_chapter?

        target_page_index = find_chapter_start_page(@reader.current_chapter - 1)
        if target_page_index
          @reader.current_page_index = target_page_index
          @reader.current_chapter -= 1
        end
      end

      def prev_chapter_absolute
        @reader.current_chapter -= 1
        @reader.send(:reset_pages)
      end

      def can_go_to_prev_chapter?
        @reader.current_chapter.positive?
      end
    end
  end
end
