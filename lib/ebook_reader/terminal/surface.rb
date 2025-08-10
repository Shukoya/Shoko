# frozen_string_literal: true

require_relative 'terminal'

module EbookReader
  module TerminalAbstraction
    # Surface provides bounded rendering with semantic styling methods
    class Surface
      def initialize(terminal = Interface.instance)
        @terminal = terminal
      end

      # === Core Writing ===

      def write(bounds, row, col, text)
        return if bounds.height <= 0 || bounds.width <= 0

        abs_row = bounds.y + row - 1
        abs_col = bounds.x + col - 1

        return if abs_row < bounds.y || abs_row > bounds.bottom
        return if abs_col > bounds.right

        max_width = bounds.right - abs_col + 1
        clipped = text.to_s[0, max_width]
        return if clipped.nil? || clipped.empty?

        @terminal.write(abs_row, abs_col, clipped)
      end

      # === Semantic Styling Methods ===

      def write_primary(bounds, row, col, text)
        write(bounds, row, col, @terminal.primary_text(text))
      end

      def write_secondary(bounds, row, col, text)
        write(bounds, row, col, @terminal.secondary_text(text))
      end

      def write_accent(bounds, row, col, text)
        write(bounds, row, col, @terminal.accent_text(text))
      end

      def write_success(bounds, row, col, text)
        write(bounds, row, col, @terminal.success_text(text))
      end

      def write_warning(bounds, row, col, text)
        write(bounds, row, col, @terminal.warning_text(text))
      end

      def write_error(bounds, row, col, text)
        write(bounds, row, col, @terminal.error_text(text))
      end

      def write_highlight(bounds, row, col, text)
        write(bounds, row, col, @terminal.highlight_text(text))
      end

      def write_selected(bounds, row, col, text)
        write(bounds, row, col, @terminal.selected_text(text))
      end

      def write_dimmed(bounds, row, col, text)
        write(bounds, row, col, @terminal.dimmed_text(text))
      end

      def write_chapter_info(bounds, row, col, text)
        write(bounds, row, col, @terminal.chapter_info(text))
      end

      def write_progress_info(bounds, row, col, text)
        write(bounds, row, col, @terminal.progress_info(text))
      end

      def write_mode_indicator(bounds, row, col, text)
        write(bounds, row, col, @terminal.mode_indicator(text))
      end

      def write_status_message(bounds, row, col, text)
        write(bounds, row, col, @terminal.status_message(text))
      end

      def write_divider(bounds, row, col)
        write(bounds, row, col, @terminal.divider)
      end

      def write_navigation_hint(bounds, row, col, text)
        write(bounds, row, col, @terminal.navigation_hint(text))
      end

      def write_content_text(bounds, row, col, text)
        write(bounds, row, col, @terminal.content_text(text))
      end

      def write_selected_item(bounds, row, col, text)
        write(bounds, row, col, @terminal.selected_item(text))
      end

      def write_unselected_item(bounds, row, col, text)
        write(bounds, row, col, @terminal.unselected_item(text))
      end

      def write_cursor_indicator(bounds, row, col)
        write(bounds, row, col, @terminal.cursor_indicator)
      end

      def write_page_indicator(bounds, row, col, text)
        write(bounds, row, col, @terminal.page_indicator(text))
      end

      # === Drawing Helpers ===

      def draw_divider_column(bounds, col_width)
        (3..[bounds.height - 1, 4].max).each do |row|
          write_divider(bounds, row, col_width + 3)
        end
      end

      def draw_title_bar(bounds, title, max_width = nil)
        max_width ||= bounds.width - 2
        clipped_title = title[0, max_width].to_s
        write_accent(bounds, 1, 1, clipped_title)
      end

      def draw_navigation_footer(bounds, text)
        write_navigation_hint(bounds, bounds.height, 1, text)
      end
    end
  end
end
