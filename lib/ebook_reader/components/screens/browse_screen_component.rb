# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module EbookReader
  module Components
    module Screens
      # Browse screen component that renders the book browsing interface
      class BrowseScreenComponent < BaseComponent
        include Constants::UIConstants
        include UI::TextUtils

        BookItemCtx = Struct.new(:row, :width, :book, :selected, keyword_init: true)

        def initialize(catalog_service, state)
          super()
          @catalog = catalog_service
          @state = state
          @filtered_epubs = []

          # Observe state changes for search and selection
          @state.add_observer(self, %i[menu browse_selected], %i[menu search_query],
                              %i[menu search_active])
        end

        def state_changed(path, _old_value, _new_value)
          case path
          when %i[menu search_query]
            filter_books
          end
        end

        def filtered_epubs=(books)
          @filtered_epubs = books || []
        end

        def selected
          EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state)
        end

        def navigate(key)
          return unless @filtered_epubs.any?

          current = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state)
          max_index = @filtered_epubs.length - 1

          new_selected = case key
                         when :up then [current - 1, 0].max
                         when :down then [current + 1, max_index].min
                         else current
                         end

          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: new_selected))
        end

        def selected_book
          browse_selected = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state)
          @filtered_epubs[browse_selected]
        end

        # Expose filtered list count for navigation logic integration
        def filtered_count
          (@filtered_epubs || []).length
        end

        # Expose random access by index (read-only)
        def book_at(index)
          (@filtered_epubs || [])[index]
        end

        def do_render(surface, bounds)
          @filtered_epubs ||= []
          height = bounds.height
          width = bounds.width

          # Header (show visual indicator when search is active)
          mode = @state.get(%i[menu mode])
          search_active = @state.get(%i[menu search_active])
          in_search = (mode == :search) || search_active
          if in_search
            title = "#{COLOR_TEXT_ACCENT}📚 Browse Books  [SEARCH]#{Terminal::ANSI::RESET}"
            right_text = "#{COLOR_TEXT_DIM}[/] Exit Search#{Terminal::ANSI::RESET}"
          else
            title = "#{COLOR_TEXT_ACCENT}📚 Browse Books#{Terminal::ANSI::RESET}"
            right_text = "#{COLOR_TEXT_DIM}[r] Refresh [ESC] Back#{Terminal::ANSI::RESET}"
          end
          surface.write(bounds, 1, 2, title)
          surface.write(bounds, 1, [width - 30, 40].max, right_text)

          # Search bar
          surface.write(bounds, 3, 2, "#{COLOR_TEXT_PRIMARY}Search: #{Terminal::ANSI::RESET}")
          search_query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state)
          search_display = search_query.dup
          cursor_pos = EbookReader::Domain::Selectors::MenuSelectors.search_cursor(@state).to_i.clamp(
            0, search_display.length
          )
          search_display.insert(cursor_pos, '_')
          surface.write(bounds, 3, 10, SELECTION_HIGHLIGHT + search_display + Terminal::ANSI::RESET)

          # Status from scanner
          render_status(surface, bounds, width, height)

          # Books list or empty state
          if @filtered_epubs.nil? || @filtered_epubs.empty?
            render_empty_state(surface, bounds, width, height)
          else
            render_books_list(surface, bounds, width, height)
          end

          # Footer
          book_count = @filtered_epubs&.length.to_i
          hint = if in_search
                   "#{book_count} books • ↑↓ Navigate • Enter Open • / Exit Search"
                 else
                   "#{book_count} books • ↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back"
                 end
          surface.write(bounds, height - 1, [(width - hint.length) / 2, 1].max,
                        COLOR_TEXT_DIM + hint + Terminal::ANSI::RESET)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def filter_books
          query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state)
          books = @catalog.entries || []
          return @filtered_epubs = books if query.nil? || query.empty?

          q = query.downcase
          @filtered_epubs = books.select do |book|
            name = book['name']&.downcase
            author = book['author']&.downcase
            (name && name.include?(q)) || (author && author.include?(q))
          end
        end

        def render_status(surface, bounds, _width, _height)
          status = @catalog.scan_status
          return unless status

          msg = @catalog.scan_message || ''
          text = case status
                 when :scanning then "#{COLOR_TEXT_WARNING}⟳ #{msg}#{Terminal::ANSI::RESET}"
                 when :error    then "#{COLOR_TEXT_ERROR}✗ #{msg}#{Terminal::ANSI::RESET}"
                 when :done     then "#{COLOR_TEXT_SUCCESS}✓ #{msg}#{Terminal::ANSI::RESET}"
                 else ''
                 end
          surface.write(bounds, 4, 2, text) unless text.empty?
        end

        def render_empty_state(surface, bounds, width, height)
          status = @catalog.scan_status
          empty_text = if status == :scanning
                         "#{COLOR_TEXT_WARNING}⟳ Scanning for books...#{Terminal::ANSI::RESET}"
                       else
                         "#{COLOR_TEXT_DIM}No matching books#{Terminal::ANSI::RESET}"
                       end
          surface.write(bounds, height / 2, [(width - 20) / 2, 1].max, empty_text)
        end

        def render_books_list(surface, bounds, width, height)
          list_start_row = 6
          list_height = height - list_start_row - 2
          return if list_height <= 0

          selected = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state)
          start_index, visible_books = UI::ListHelpers.slice_visible(@filtered_epubs, list_height, selected)

          # Draw header row and divider
          draw_list_header(surface, bounds, width, list_start_row - 1)
          list_start_row += 1

          # Inline loading info
          loading_path = @state.get(%i[menu loading_path])
          loading_active = @state.get(%i[menu loading_active])
          loading_progress = (@state.get(%i[menu loading_progress]) || 0.0).to_f

          current_row = list_start_row
          visible_books.each_with_index do |book, index|
            is_selected = (start_index + index) == selected
            ctx = BookItemCtx.new(row: current_row, width: width, book: book, selected: is_selected)
            render_book_item(surface, bounds, ctx)

            next_row = current_row + 1
            if loading_active && loading_path == book['path'] && next_row < bounds.bottom
              draw_inline_progress(surface, bounds, width, next_row, loading_progress)
              current_row += 2
            else
              current_row += 1
            end
          end
        end

        def render_book_item(surface, bounds, ctx)
          book = ctx.book
          path = book['path']
          meta = @catalog.metadata_for(path)

          title = (meta[:title] || book['name'] || 'Unknown').to_s
          authors = (meta[:author_str] || '').to_s
          year = (meta[:year] || '').to_s
          size_mb = format_size(book['size'] || @catalog.size_for(path))

          # Compute column widths
          pointer_w = 2
          gap = 2
          remaining = ctx.width - pointer_w - (gap * 3)
          year_w = 6
          size_w = 8
          author_w = [(remaining * 0.25).to_i, 12].max.clamp(12, remaining - 20 - year_w - size_w)
          title_w = [remaining - author_w - year_w - size_w, 20].max

          # Compose columns
          sel = ctx.selected
          pointer = sel ? '▸ ' : '  '
          title_col = truncate_text(title, title_w).ljust(title_w)
          author_col = truncate_text(authors, author_w).ljust(author_w)
          year_col = year[0, 4].ljust(year_w)
          size_col = size_mb.rjust(size_w)

          line = [title_col, author_col, year_col, size_col].join(' ' * gap)
          r = ctx.row
          if sel
            surface.write(bounds, r, 1, SELECTION_HIGHLIGHT + pointer + line + Terminal::ANSI::RESET)
          else
            surface.write(bounds, r, 1, COLOR_TEXT_PRIMARY + pointer + line + Terminal::ANSI::RESET)
          end
        end

        def draw_list_header(surface, bounds, width, row)
          return if row < 5

          pointer_w = 2
          gap = 2
          remaining = width - pointer_w - (gap * 3)
          year_w = 6
          size_w = 8
          author_w = [(remaining * 0.25).to_i, 12].max.clamp(12, remaining - 20 - year_w - size_w)
          title_w = [remaining - author_w - year_w - size_w, 20].max

          headers = [
            'Title'.ljust(title_w),
            'Author(s)'.ljust(author_w),
            'Year'.ljust(year_w),
            'Size'.rjust(size_w),
          ].join(' ' * gap)

          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::LIGHT_GREY
          surface.write(bounds, row, 1, header_style + (' ' * pointer_w) + headers + Terminal::ANSI::RESET)
          # Divider line
          divider = ('─' * [width - 2, 1].max)
          surface.write(bounds, row + 1, 1, COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def format_size(bytes)
          mb = (bytes.to_f / (1024 * 1024)).round(1)
          format('%.1f MB', mb)
        end

        def draw_inline_progress(surface, bounds, width, row, progress)
          bar_col = 3
          usable = [width - bar_col - 2, 10].max
          filled = (usable * progress.to_f.clamp(0.0, 1.0)).round
          green = Terminal::ANSI::BRIGHT_GREEN
          grey  = Terminal::ANSI::GRAY
          reset = Terminal::ANSI::RESET
          track = (green + ('━' * filled)) + (grey + ('━' * (usable - filled))) + reset
          surface.write(bounds, row, bar_col, track)
        end

        # truncate_text provided by UI::TextUtils
      end
    end
  end
end
