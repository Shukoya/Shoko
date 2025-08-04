# frozen_string_literal: true

module EbookReader
  module ReaderDisplay
    # Handles column rendering logic
    module ColumnRenderer
      def draw_column(context)
        return if invalid_column_params?(context.lines, context.dimensions.width,
                                         context.dimensions.height)

        render_column_content(context)
        draw_page_number(context) if context.show_page_num
      end

      private

      def render_column_content(context)
        actual_height = calculate_actual_height(context.dimensions.height)
        end_offset = [context.offset + actual_height, context.lines.size].min
        drawing_context = build_line_drawing_context(context, actual_height, end_offset)
        draw_lines(drawing_context)
      end

      def draw_lines(context)
        visible_range = calculate_visible_line_range(context)
        visible_range.each_with_index do |line_index, display_index|
          line_params = build_line_render_params(context, line_index, display_index)
          render_single_line(**line_params)
        end
      end

      def draw_page_number(context)
        return unless should_draw_page_number?(context)

        page_info = calculate_page_info(context)
        draw_page_text(page_info, context)
      end

      def build_line_drawing_context(context, actual_height, end_offset)
        LineDrawingContext.new(
          lines: context.lines,
          start_offset: context.offset,
          end_offset: end_offset,
          position: context.position,
          dimensions: context.dimensions,
          actual_height: actual_height
        )
      end

      def build_line_render_params(context, line_index, display_index)
        {
          line: context.lines[line_index],
          row: context.position.row + display_index,
          col: context.position.col,
          width: context.dimensions.width,
          base_row: context.position.row,
          height: context.dimensions.height,
        }
      end

      def calculate_visible_line_range(context)
        context.start_offset...context.end_offset
      end

      def render_single_line(line:, row:, col:, width:, base_row:, height:)
        return if row_exceeds_bounds?(row, base_row, height)

        draw_line(
          DrawingParams.new(
            line: line,
            position: Models::Position.new(row: row, col: col),
            width: width
          )
        )
      end

      def row_exceeds_bounds?(row, base_row, height)
        row >= base_row + height
      end

      def invalid_column_params?(lines, width, height)
        lines.nil? || lines.empty? || width < 10 || height < 1
      end

      def calculate_actual_height(height)
        height
      end

      def should_draw_page_number?(context)
        @config.show_page_numbers &&
          context.lines&.size&.positive? &&
          calculate_actual_height(context.dimensions.height).positive?
      end

      def calculate_page_info(context)
        actual_height = calculate_actual_height(context.dimensions.height)
        page_num = calculate_current_page_number(context.offset, actual_height)
        total_pages = calculate_total_pages(context.lines.size, actual_height)

        {
          text: "#{page_num}/#{total_pages}",
          row: context.position.row + context.dimensions.height - 1,
        }
      end

      def calculate_current_page_number(offset, height)
        (offset / height) + 1
      end

      def calculate_total_pages(total_lines, height)
        [(total_lines.to_f / height).ceil, 1].max
      end

      def draw_page_text(page_info, context)
        return if page_info[:row] >= Terminal.size[0] - 2

        col = calculate_page_text_column(page_info, context)
        text = formatted_page_text(page_info[:text])
        Terminal.write(page_info[:row], col, text)
      end

      def calculate_page_text_column(page_info, context)
        context.position.col +
          [(context.dimensions.width - page_info[:text].length) / 2, 0].max
      end

      def formatted_page_text(text)
        Terminal::ANSI::DIM + Terminal::ANSI::GRAY + text + Terminal::ANSI::RESET
      end
    end
  end
end
