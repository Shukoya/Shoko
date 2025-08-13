# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Browse screen component that renders the book browsing interface
      class BrowseScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(scanner, state)
          super()
          @scanner = scanner
          @state = state
          @filtered_epubs = []
          
          # Observe state changes for search and selection
          @state.add_observer(self, [:menu, :browse_selected], [:menu, :search_query], [:menu, :search_active])
        end

        def state_changed(path, _old_value, _new_value)
          case path
          when [:menu, :search_query]
            filter_books
          end
        end

        def filtered_epubs=(books)
          @filtered_epubs = books || []
        end

        def selected
          @state.browse_selected
        end

        def navigate(key)
          return unless @filtered_epubs.any?

          current = @state.browse_selected
          max_index = @filtered_epubs.length - 1

          new_selected = case key
                        when :up then [current - 1, 0].max
                        when :down then [current + 1, max_index].min
                        else current
                        end

          @state.browse_selected = new_selected
        end

        def selected_book
          @filtered_epubs[@state.browse_selected]
        end

        def do_render(surface, bounds)
          @filtered_epubs ||= []
          height = bounds.height
          width = bounds.width

          # Header
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}📚 Browse Books#{Terminal::ANSI::RESET}")
          right_text = "#{COLOR_TEXT_DIM}[r] Refresh [ESC] Back#{Terminal::ANSI::RESET}"
          surface.write(bounds, 1, [width - 30, 40].max, right_text)

          # Search bar
          surface.write(bounds, 3, 2, "#{COLOR_TEXT_PRIMARY}Search: #{Terminal::ANSI::RESET}")
          search_query = @state.search_query || ''
          search_display = search_query.dup
          cursor_pos = @state.search_cursor.to_i.clamp(0, search_display.length)
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
          hint = "#{book_count} books • ↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back"
          surface.write(bounds, height - 1, [(width - hint.length) / 2, 1].max,
                        COLOR_TEXT_DIM + hint + Terminal::ANSI::RESET)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def filter_books
          query = @state.search_query
          return @filtered_epubs = @scanner.epubs || [] if query.nil? || query.empty?

          all_books = @scanner.epubs || []
          @filtered_epubs = all_books.select do |book|
            book['name']&.downcase&.include?(query.downcase) ||
              book['author']&.downcase&.include?(query.downcase)
          end
        end

        def render_status(surface, bounds, width, _height)
          status = @scanner.scan_status
          return unless status

          text = case status
                when :scanning then "#{COLOR_TEXT_WARNING}⟳ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                when :error then "#{COLOR_TEXT_ERROR}✗ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                when :done then "#{COLOR_TEXT_SUCCESS}✓ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                else ''
                end
          surface.write(bounds, 4, 2, text) unless text.empty?
        end

        def render_empty_state(surface, bounds, width, height)
          status = @scanner.scan_status
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

          selected = @state.browse_selected
          start_index, visible_books = calculate_visible_range(list_height, selected)

          visible_books.each_with_index do |book, index|
            row = list_start_row + index
            is_selected = (start_index + index) == selected

            render_book_item(surface, bounds, row, width, book, is_selected)
          end
        end

        def calculate_visible_range(list_height, selected)
          total_books = @filtered_epubs.length
          start_index = 0

          if selected >= list_height
            start_index = selected - list_height + 1
          end

          if total_books > list_height
            start_index = [start_index, total_books - list_height].min
          end

          end_index = [start_index + list_height - 1, total_books - 1].min
          visible_books = @filtered_epubs[start_index..end_index] || []

          [start_index, visible_books]
        end

        def render_book_item(surface, bounds, row, width, book, is_selected)
          title = book['name'] || 'Unknown Title'
          author = book['author'] || 'Unknown Author'
          
          # Truncate long titles/authors
          max_title_length = [width - 40, 30].max
          title = truncate_text(title, max_title_length)
          author = truncate_text(author, 20)

          prefix = is_selected ? '▶ ' : '  '
          text = "#{prefix}#{title}"
          text += " #{COLOR_TEXT_DIM}by #{author}#{Terminal::ANSI::RESET}" if author != 'Unknown Author'

          if is_selected
            surface.write(bounds, row, 1, SELECTION_HIGHLIGHT + text + Terminal::ANSI::RESET)
          else
            surface.write(bounds, row, 1, COLOR_TEXT_PRIMARY + text + Terminal::ANSI::RESET)
          end
        end

        def truncate_text(text, max_length)
          return text if text.length <= max_length
          "#{text[0...max_length - 3]}..."
        end
      end
    end
  end
end