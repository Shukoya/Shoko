# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    class ContentComponent < BaseComponent
      def initialize(controller)
        @controller = controller
        state = @controller.instance_variable_get(:@state)
        # Observe core fields that affect content rendering
        state.add_observer(self, :current_chapter, :left_page, :right_page,
                           :single_page, :current_page_index, :mode)
        @needs_redraw = true
      end

      # Flexible to fill remaining space
      def preferred_height(_available_height)
        nil
      end

      def render(surface, bounds)
        state = @controller.instance_variable_get(:@state)
        config = @controller.config
        doc = @controller.instance_variable_get(:@doc)

        # Reset rendered lines registry for selection/highlighting
        @controller.instance_variable_set(:@rendered_lines, {})

        # If nothing relevant changed since last render, still draw (safe),
        # but we can short-circuit expensive recompute later using @needs_redraw
        case state.mode
        when :help
          render_help(surface, bounds)
        when :toc
          render_toc(surface, bounds, doc, state.toc_selected || 0)
        when :bookmarks
          render_bookmarks(surface, bounds, doc)
        else
          render_reading(surface, bounds, doc, state, config)
        end
        @needs_redraw = false
      end

      private

      def render_reading(surface, bounds, doc, state, config)
        bounds.height
        bounds.width

        if config.view_mode == :split
          render_split(surface, bounds, doc, state, config)
        elsif config.page_numbering_mode == :dynamic
          render_single_dynamic(surface, bounds, doc, state, config)
        else
          render_single_absolute(surface, bounds, doc, state, config)
        end
      end

      def render_split(surface, bounds, doc, state, config)
        chapter = doc.get_chapter(state.current_chapter)
        return unless chapter

        col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
        display_height = adjust_for_line_spacing(content_height, config.line_spacing)
        wrapped = @controller.wrap_lines(chapter.lines || [], col_width)

        # Chapter info on first row
        chapter_info = "[#{state.current_chapter + 1}] #{chapter.title || 'Unknown'}"
        surface.write(bounds, 1, 1,
                      Terminal::ANSI::BLUE + chapter_info[0, bounds.width - 2].to_s + Terminal::ANSI::RESET)

        # Left column
        draw_column(surface, bounds,
                    lines: wrapped,
                    offset: state.left_page || 0,
                    col_width: col_width,
                    height: display_height,
                    row: 3, col: 1,
                    line_spacing: config.line_spacing)

        # Divider
        draw_divider(surface, bounds, col_width)

        # Right column
        draw_column(surface, bounds,
                    lines: wrapped,
                    offset: state.right_page || 0,
                    col_width: col_width,
                    height: display_height,
                    row: 3, col: col_width + 5,
                    line_spacing: config.line_spacing)
      end

      def render_single_dynamic(surface, bounds, _doc, state, config)
        page_manager = @controller.instance_variable_get(:@page_manager)
        return unless page_manager

        page_data = page_manager.get_page(state.current_page_index)
        return unless page_data

        col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
        col_start = [(bounds.width - col_width) / 2, 1].max
        start_row = calculate_center_start_row(content_height, page_data[:lines].size,
                                               config.line_spacing)

        page_data[:lines].each_with_index do |line, idx|
          row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
          break if row > bounds.height - 2

          draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width)
        end
      end

      def render_single_absolute(surface, bounds, doc, state, config)
        chapter = doc.get_chapter(state.current_chapter)
        return unless chapter

        col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
        col_start = [(bounds.width - col_width) / 2, 1].max
        displayable = adjust_for_line_spacing(content_height, config.line_spacing)
        wrapped = @controller.wrap_lines(chapter.lines || [], col_width)
        lines = wrapped.slice(state.single_page || 0, displayable) || []

        actual_lines = config.line_spacing == :relaxed ? [(lines.size * 2) - 1, 0].max : lines.size
        padding = (content_height - actual_lines)
        start_row = [3 + (padding / 2), 3].max

        lines.each_with_index do |line, idx|
          row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
          break if row >= (3 + displayable)

          draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width)
        end
      end

      def draw_divider(surface, bounds, col_width)
        (3..[bounds.height - 1, 4].max).each do |row|
          surface.write(bounds, row, col_width + 3,
                        "#{Terminal::ANSI::GRAY}│#{Terminal::ANSI::RESET}")
        end
      end

      def draw_column(surface, bounds, lines:, offset:, col_width:, height:, row:, col:,
                      line_spacing:)
        display_lines = lines.slice(offset, height) || []
        display_lines.each_with_index do |line, idx|
          r = row + (line_spacing == :relaxed ? idx * 2 : idx)
          break if r >= bounds.height - 1

          draw_line(surface, bounds, line: line, row: r, col: col, width: col_width)
        end
      end

      def draw_line(surface, bounds, line:, row:, col:, width:)
        # Keep for highlighting integrations
        text = line.to_s[0, width]
        config = @controller.config
        if config.respond_to?(:highlight_keywords) && config.highlight_keywords
          text = highlight_keywords(text)
        end
        text = highlight_quotes(text) if config.highlight_quotes

        abs_row = bounds.y + row - 1
        (@controller.instance_variable_get(:@rendered_lines) || {})[abs_row] = {
          col: bounds.x + col - 1,
          text: text,
        }

        surface.write(bounds, row, col, Terminal::ANSI::WHITE + text + Terminal::ANSI::RESET)
      end

      def layout_metrics(width, height, view_mode)
        col_width = if view_mode == :split
                      [(width - 3) / 2, 20].max
                    else
                      (width * 0.9).to_i.clamp(30, 120)
                    end
        content_height = [height - 2, 1].max
        [col_width, content_height]
      end

      def adjust_for_line_spacing(height, line_spacing)
        return 1 if height <= 0

        line_spacing == :relaxed ? [height / 2, 1].max : height
      end

      def calculate_center_start_row(content_height, lines_count, line_spacing)
        actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
        padding = [(content_height - actual_lines) / 2, 0].max
        [3 + padding, 3].max
      end

      # ===== Non-reading screens =====
      def render_help(surface, bounds)
        lines = [
          '',
          'Navigation Keys:',
          '  j / ↓     Scroll down',
          '  k / ↑     Scroll up',
          '  l / →     Next page',
          '  h / ←     Previous page',
          '  SPACE     Next page',
          '  n         Next chapter',
          '  p         Previous chapter',
          '  g         Go to beginning of chapter',
          '  G         Go to end of chapter',
          '',
          'View Options:',
          '  v         Toggle split/single view',
          '  P         Toggle page numbering mode (Absolute/Dynamic)',
          '  + / -     Adjust line spacing',
          '',
          'Features:',
          '  t         Show Table of Contents',
          '  b         Add a bookmark',
          '  B         Show bookmarks',
          '',
          'Other Keys:',
          '  ?         Show/hide this help',
          '  q         Quit to menu',
          '  Q         Quit application',
          '',
          '',
          'Press any key to return to reading...',
        ]

        start_row = [(bounds.height - lines.size) / 2, 1].max
        lines.each_with_index do |line, idx|
          row = start_row + idx
          break if row >= bounds.height - 2

          col = [(bounds.width - line.length) / 2, 1].max
          surface.write(bounds, row, col, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
        end
      end

      def render_toc(surface, bounds, doc, selected_index)
        surface.write(bounds, 1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📖 Table of Contents#{Terminal::ANSI::RESET}")
        surface.write(bounds, 1, [bounds.width - 30, 40].max,
                      "#{Terminal::ANSI::DIM}[t/ESC] Back to Reading#{Terminal::ANSI::RESET}")

        list_start = 4
        list_height = bounds.height - 6
        chapters = doc.chapters
        return if chapters.empty?

        visible_start = [selected_index - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, chapters.length].min
        (visible_start...visible_end).each_with_index do |idx, row|
          chapter = chapters[idx]
          line = (chapter.title || 'Untitled')[0, bounds.width - 6]
          y = list_start + row
          if idx == selected_index
            surface.write(bounds, y, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
            surface.write(bounds, y, 4, Terminal::ANSI::BRIGHT_WHITE + line + Terminal::ANSI::RESET)
          else
            surface.write(bounds, y, 4, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
          end
        end

        surface.write(bounds, bounds.height - 1, 2,
                      "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{Terminal::ANSI::RESET}")
      end

      def render_bookmarks(surface, bounds, doc)
        bookmarks = @controller.instance_variable_get(:@bookmarks) || []
        surface.write(bounds, 1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}🔖 Bookmarks#{Terminal::ANSI::RESET}")
        surface.write(bounds, 1, [bounds.width - 40, 40].max,
                      "#{Terminal::ANSI::DIM}[B/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")

        if bookmarks.empty?
          surface.write(bounds, bounds.height / 2, (bounds.width - 30) / 2,
                        "#{Terminal::ANSI::DIM}No bookmarks yet. Press \\\"b\\\" while reading to add one.#{Terminal::ANSI::RESET}")
          return
        end

        list_start = 4
        list_height = (bounds.height - 6) / 2
        selected = @controller.instance_variable_get(:@state).bookmark_selected || 0
        visible_start = [selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, bookmarks.length].min
        (visible_start...visible_end).each_with_index do |idx, row_idx|
          bookmark = bookmarks[idx]
          chapter = doc.get_chapter(bookmark.chapter_index)
          chapter_title = chapter&.title || "Chapter #{bookmark.chapter_index + 1}"

          row = list_start + (row_idx * 2)
          is_selected = (idx == selected)
          draw_bookmark_item(surface, bounds, row, bounds.width, bookmark, chapter_title,
                             is_selected)
        end
      end

      def draw_bookmark_item(surface, bounds, row, width, bookmark, chapter_title, selected)
        chapter_text = "Ch. #{bookmark.chapter_index + 1}: #{chapter_title[0, width - 20]}"
        text_snippet = bookmark.text_snippet[0, width - 8]

        if selected
          surface.write(bounds, row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
          surface.write(bounds, row, 4, "#{Terminal::ANSI::BRIGHT_WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")
          surface.write(bounds, row + 1, 6,
                        "#{Terminal::ANSI::ITALIC}#{Terminal::ANSI::GRAY}#{text_snippet}#{Terminal::ANSI::RESET}")
        else
          surface.write(bounds, row, 4, "#{Terminal::ANSI::WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")
          surface.write(bounds, row + 1, 6,
                        "#{Terminal::ANSI::DIM}#{Terminal::ANSI::GRAY}#{text_snippet}#{Terminal::ANSI::RESET}")
        end
      end

      def highlight_keywords(line)
        line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
          Terminal::ANSI::CYAN + match + Terminal::ANSI::WHITE
        end
      end

      def highlight_quotes(line)
        line.gsub(Constants::QUOTE_PATTERNS) do |match|
          Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + Terminal::ANSI::WHITE
        end
      end
    end
  end
end

# Observer callback triggered by ReaderState
def state_changed(_field, _old_value, _new_value)
  @needs_redraw = true
end
