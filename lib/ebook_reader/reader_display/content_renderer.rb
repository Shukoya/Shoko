# frozen_string_literal: true

module EbookReader
  module ReaderDisplay
    # Renders help and table of contents screens
    module ContentRenderer
      def draw_help_screen(height, width)
        start_row = [(height - HELP_LINES.size) / 2, 1].max

        HELP_LINES.each_with_index do |line, idx|
          row = start_row + idx
          break if row >= height - 2

          draw_help_line(line, row, width)
        end
      end

      def draw_help_line(line, row, width)
        col = [(width - line.length) / 2, 1].max
        Terminal.write(row, col, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
      end

      def build_help_lines
        HELP_LINES
      end

      def draw_toc_screen(height, width)
        draw_toc_header(width)
        draw_toc_list(height, width)
        draw_toc_footer(height)
      end

      def draw_toc_header(width)
        Terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📖 Table of Contents#{Terminal::ANSI::RESET}")
        Terminal.write(1, [width - 30, 40].max,
                       "#{Terminal::ANSI::DIM}[t/ESC] Back to Reading#{Terminal::ANSI::RESET}")
      end

      def draw_toc_list(height, width)
        list_start = 4
        list_height = height - 6
        chapters = @doc.chapters
        return if chapters.empty?

        visible_range = calculate_toc_visible_range(list_height, chapters.length)
        context = TocItemsContext.new(visible_range, chapters, list_start, width, @toc_selected)
        draw_toc_items(context)
      end

      def calculate_toc_visible_range(list_height, chapter_count)
        visible_start = [@toc_selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, chapter_count].min
        visible_start...visible_end
      end

      TocItemsContext = Struct.new(:range, :chapters, :list_start, :width, :selected_index)

      def draw_toc_items(context)
        context.range.each_with_index do |idx, row|
          chapter = context.chapters[idx]
          line = chapter.title || 'Untitled'
          line_context = TocLineContext.new(idx, line, context.list_start + row, context.width,
                                            idx == context.selected_index)
          draw_toc_line(line_context)
        end
      end

      TocLineContext = Struct.new(:index, :line, :row, :width, :selected)

      def draw_toc_line(context)
        if context.selected
          draw_selected_toc_line(context)
        else
          draw_unselected_toc_line(context)
        end
      end

      def draw_toc_footer(height)
        Terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{Terminal::ANSI::RESET}")
      end

      private

      def draw_selected_toc_line(context)
        Terminal.write(context.row, 2, toc_pointer)
        Terminal.write(context.row, 4, selected_toc_text(context.line, context.width))
      end

      def draw_unselected_toc_line(context)
        Terminal.write(context.row, 4, unselected_toc_text(context.line, context.width))
      end

      def toc_pointer
        "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}"
      end

      def selected_toc_text(line, width)
        Terminal::ANSI::BRIGHT_WHITE + line[0, width - 6] + Terminal::ANSI::RESET
      end

      def unselected_toc_text(line, width)
        Terminal::ANSI::WHITE + line[0, width - 6] + Terminal::ANSI::RESET
      end
    end
  end
end
