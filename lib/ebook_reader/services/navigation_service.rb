# frozen_string_literal: true

require_relative 'layout_service'

module EbookReader
  module Services
    # A service that provides methods for navigating through the book. It includes
    # methods for moving to the next and previous pages, chapters, and to the end
    # of the book.
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
        col_width, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                              @reader.config.view_mode)
        content_height = Services::LayoutService.adjust_for_line_spacing(content_height,
                                                                         @reader.config.line_spacing)
        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return {} unless chapter

        max_page = compute_max_page(chapter, col_width, content_height)
        { chapter: chapter, content_height: content_height, max_page: max_page }
      end

      def compute_max_page(chapter, col_width, content_height)
        wrapped = @reader.wrap_lines(chapter.lines || [], col_width)
        
        if @reader.config.view_mode == :split
          # In split mode, we show 2 * content_height lines per "page turn"
          # So the max starting position for left page is total_lines - (2 * content_height)
          [wrapped.size - (2 * content_height), 0].max
        else
          # In single mode, max starting position is total_lines - content_height  
          [wrapped.size - content_height, 0].max
        end
      end

      def navigate_to_next_page(metrics)
        if @reader.config.view_mode == :split
          navigate_to_next_page_split(metrics)
        else
          navigate_to_next_page_single(metrics)
        end
      end

      def navigate_to_next_page_split(metrics)
        if @reader.left_page < metrics[:max_page]
          @reader.left_page += (2 * metrics[:content_height])
          if @reader.left_page > metrics[:max_page]
            @reader.left_page = metrics[:max_page]
          end
          @reader.right_page = @reader.left_page + metrics[:content_height]
        elsif @reader.current_chapter < @reader.doc.chapter_count - 1
          next_chapter
        end
      end

      def navigate_to_next_page_single(metrics)
        if @reader.single_page < metrics[:max_page]
          @reader.single_page = [@reader.single_page + metrics[:content_height], metrics[:max_page]].min
        elsif @reader.current_chapter < @reader.doc.chapter_count - 1
          next_chapter
        end
      end

      def prev_page_absolute
        metrics = calculate_page_metrics
        return unless metrics[:chapter]

        if @reader.config.view_mode == :split
          navigate_to_prev_page_split(metrics)
        else
          navigate_to_prev_page_single(metrics)
        end
      end

      def navigate_to_prev_page_split(metrics)
        if @reader.left_page > 0
          @reader.left_page -= (2 * metrics[:content_height])
          if @reader.left_page < 0
            @reader.left_page = 0
          end
          @reader.right_page = @reader.left_page + metrics[:content_height]
        elsif @reader.current_chapter > 0
          prev_chapter
          position_at_chapter_end
        end
      end

      def navigate_to_prev_page_single(metrics)
        if @reader.single_page > 0
          @reader.single_page = [@reader.single_page - metrics[:content_height], 0].max
        elsif @reader.current_chapter > 0
          prev_chapter
          position_at_chapter_end
        end
      end

      def initialize_pages
        metrics = calculate_page_metrics
        return unless metrics[:content_height] > 0

        if @reader.config.view_mode == :split
          @reader.left_page = 0
          @reader.right_page = metrics[:content_height]
        else
          @reader.single_page = 0
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
        return unless target_page_index

        @reader.current_page_index = target_page_index
        @reader.current_chapter += 1
      end

      def next_chapter_absolute
        @reader.current_chapter += 1
        reset_pages
        @reader.save_progress
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
        return unless target_page_index

        @reader.current_page_index = target_page_index
        @reader.current_chapter -= 1
      end

      def prev_chapter_absolute
        @reader.current_chapter -= 1
        reset_pages
      end

      def can_go_to_prev_chapter?
        @reader.current_chapter.positive?
      end

      # Main navigation methods - should be public
      def next_page
        if @reader.config.page_numbering_mode == :dynamic
          next_page_dynamic
        else
          next_page_absolute
        end
      end

      def prev_page
        if @reader.config.page_numbering_mode == :dynamic
          prev_page_dynamic
        else
          prev_page_absolute
        end
      end

      def next_page_dynamic
        return unless @reader.page_manager
        return unless @reader.current_page_index < @reader.page_manager.total_pages - 1

        @reader.current_page_index += 1
        update_chapter_from_page_index
      end

      def prev_page_dynamic
        return unless @reader.page_manager
        return unless @reader.current_page_index.positive?

        @reader.current_page_index -= 1
        update_chapter_from_page_index
      end

      def update_chapter_from_page_index
        page_data = @reader.page_manager.get_page(@reader.current_page_index)
        return unless page_data

        @reader.current_chapter = page_data[:chapter_index]
      end

      def scroll_down
        return if @reader.config.page_numbering_mode == :dynamic

        metrics = calculate_page_metrics
        max_page = metrics[:max_page] || 0

        if @reader.config.view_mode == :split
          @reader.left_page = [@reader.left_page + 1, max_page].min
          @reader.right_page = [@reader.right_page + 1, max_page].min
        else
          @reader.single_page = [@reader.single_page + 1, max_page].min
        end
      end

      def scroll_up
        return if @reader.config.page_numbering_mode == :dynamic

        if @reader.config.view_mode == :split
          @reader.left_page = [@reader.left_page - 1, 0].max
          @reader.right_page = [@reader.right_page - 1, 0].max
        else
          @reader.single_page = [@reader.single_page - 1, 0].max
        end
      end

      def go_to_start
        reset_pages
      end

      def reset_pages
        initialize_pages
      end

      def position_at_chapter_end
        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter&.lines

        col_width, content_height = end_of_chapter_metrics
        return unless content_height.positive?

        wrapped = @reader.wrap_lines(chapter.lines, col_width)
        max_page = [wrapped.size - content_height, 0].max
        set_page_end(max_page, content_height)
      end

      def end_of_chapter_metrics
        height, width = Terminal.size
        col_width, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                              @reader.config.view_mode)
        [col_width, Services::LayoutService.adjust_for_line_spacing(content_height, @reader.config.line_spacing)]
      end

      def set_page_end(max_page, content_height)
        if @reader.config.view_mode == :split
          @reader.right_page = max_page
          @reader.left_page = [max_page - content_height, 0].max
        else
          @reader.single_page = max_page
        end
      end

      # Make all navigation methods public
      public :next_page, :prev_page, :scroll_down, :scroll_up, :go_to_start, :go_to_end, 
             :next_chapter, :prev_chapter, :initialize_pages, :position_at_chapter_end,
             :reset_pages, :update_chapter_from_page_index
    end
  end
end
