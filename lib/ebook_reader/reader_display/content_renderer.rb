# frozen_string_literal: true

module EbookReader
  module ReaderDisplay
    # Renders help and table of contents screens
    module ContentRenderer
      def draw_help_screen(height, width)
        # Delegate to ReaderRenderer for consistent rendering pattern
        (@renderer || UI::ReaderRenderer.new(@config)).tap do |renderer|
          renderer.send(:render_help_lines, height, width, HELP_LINES)
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
        (@renderer || UI::ReaderRenderer.new(@config)).tap do |renderer|
          selected = @state&.toc_selected || 0
          renderer.send(:render_toc_screen, height, width, @doc, selected)
        end
      end

      def draw_toc_header(_width); end

      def draw_toc_list(_height, _width); end

      def calculate_toc_visible_range(list_height, chapter_count)
        selected = @state&.toc_selected || 0
        visible_start = [selected - (list_height / 2), 0].max
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

      def draw_toc_footer(_height); end

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
