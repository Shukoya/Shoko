# frozen_string_literal: true

# This file contains refactored methods extracted from Reader class
module EbookReader
  module ReaderRefactored
    # Extract complex navigation logic
    module NavigationHelpers
      def calculate_navigation_params
        height, width = Terminal.size
        col_width, content_height = get_layout_metrics(width, height)
        content_height = adjust_for_line_spacing(content_height)

        chapter = @doc.get_chapter(@current_chapter)
        return nil unless chapter

        wrapped = wrap_lines(chapter.lines || [], col_width)
        max_page = [wrapped.size - content_height, 0].max

        [content_height, max_page, wrapped]
      end

      def update_page_position_split?(direction, content_height, max_page)
        case direction
        when :next
          split_next_page?(content_height, max_page)
        when :prev
          split_prev_page?(content_height)
        end
      end

      def split_next_page?(content_height, max_page)
        return false unless @right_page < max_page

        @left_page = @right_page
        @right_page = [@right_page + content_height, max_page].min
        true
      end

      def split_prev_page?(content_height)
        return false unless @left_page.positive?

        @right_page = @left_page
        @left_page = [@left_page - content_height, 0].max
        true
      end

      def update_page_position_single?(direction, content_height, max_page)
        case direction
        when :next
          return false unless @single_page < max_page

          @single_page = [@single_page + content_height, max_page].min
          true
        when :prev
          update_single_prev_page?(content_height)
        end
      end

      def update_single_prev_page?(content_height)
        return false unless @single_page.positive?

        @single_page = [@single_page - content_height, 0].max
        true
      end
    end

    # Extract drawing helpers
    module DrawingHelpers
      LineFormatContext = Struct.new(:line, :row, :start_col, :width)
      PageIndicatorContext = Struct.new(:start_row, :start_col, :width, :height, :offset,
                                        :actual_height, :lines)
      IndicatorTextContext = Struct.new(:page_text, :start_row, :start_col, :width, :height)

      def draw_line_with_formatting(context)
        if should_highlight_line?(context.line)
          draw_highlighted_line(context.line, context.row, context.start_col, context.width)
        else
          Terminal.write(context.row, context.start_col,
                         Terminal::ANSI::WHITE + context.line[0, context.width] + Terminal::ANSI::RESET)
        end
      end

      def calculate_visible_lines(lines, offset, height)
        end_offset = [offset + height, lines.size].min
        lines[offset...end_offset] || []
      end

      def render_page_indicator(context)
        return unless should_render_indicator?(context.lines, context.actual_height)

        page_info = calculate_page_indicator_info(context.offset, context.actual_height,
                                                  context.lines)
        text_context = IndicatorTextContext.new(page_info, context.start_row, context.start_col,
                                                context.width, context.height)
        render_indicator_text(text_context)
      end

      def should_render_indicator?(lines, actual_height)
        @config.show_page_numbers && lines.size.positive? && actual_height.positive?
      end

      def calculate_page_indicator_info(offset, actual_height, lines)
        page_num = (offset / actual_height) + 1
        total_pages = [(lines.size.to_f / actual_height).ceil, 1].max
        "#{page_num}/#{total_pages}"
      end

      def render_indicator_text(context)
        page_row = context.start_row + context.height - 1
        return if page_row >= Terminal.size[0] - Constants::PAGE_NUMBER_PADDING

        col = [context.start_col + context.width - context.page_text.length, context.start_col].max
        Terminal.write(page_row, col,
                       Terminal::ANSI::DIM + Terminal::ANSI::GRAY + context.page_text + Terminal::ANSI::RESET)
      end
    end

    # Extract bookmark helpers
    module BookmarkHelpers
      def create_bookmark_data
        line_offset = @config.view_mode == :split ? @left_page : @single_page
        chapter = @doc.get_chapter(@current_chapter)
        return nil unless chapter

        text_snippet = extract_bookmark_text(chapter, line_offset)
        Models::Bookmark.new(
          chapter_index: @current_chapter,
          line_offset: line_offset,
          text_snippet: text_snippet,
          created_at: Time.now
        )
      end

      def jump_to_bookmark_position(bookmark)
        @current_chapter = bookmark.chapter_index
        self.page_offsets = bookmark.line_offset
        save_progress
        @mode = :read
      end
    end
  end
end
