# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../concerns/input_handler'

module EbookReader
  module UI
    module Screens
      # Handles browse screen rendering
      class BrowseScreen
        include EbookReader::Constants
        include EbookReader::Concerns::InputHandler

        BROWSE_FOOTER_HINTS = '↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back'

        attr_accessor :selected, :search_query, :search_cursor, :filtered_epubs, :search_active

        def initialize(scanner, _renderer = nil)
          @scanner = scanner
          @selected = 0
          @search_query = ''
          @search_cursor = 0
          @filtered_epubs = []
          @search_active = false
          @renderer = nil
        end

        def navigate(key)
          return unless @filtered_epubs.any?

          @selected = handle_navigation_keys(key, @selected, @filtered_epubs.length - 1)
        end

        def selected_book
          @filtered_epubs[@selected]
        end

        def draw(height, width)
          @filtered_epubs ||= []
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)

          # Header
          surface.write(bounds, 1, 2, "#{UIConstants::COLOR_TEXT_ACCENT}📚 Browse Books#{Terminal::ANSI::RESET}")
          right = "#{UIConstants::COLOR_TEXT_DIM}[r] Refresh [ESC] Back#{Terminal::ANSI::RESET}"
          surface.write(bounds, 1, [width - 30, 40].max, right)

          # Search
          surface.write(bounds, 3, 2, "#{UIConstants::COLOR_TEXT_PRIMARY}Search: #{Terminal::ANSI::RESET}")
          display = (@search_query || '').dup
          cur = @search_cursor.to_i.clamp(0, display.length)
          display.insert(cur, '_')
          surface.write(bounds, 3, 10, UIConstants::SELECTION_HIGHLIGHT + display + Terminal::ANSI::RESET)

          # Status
          status = @scanner.scan_status
          unless status.nil?
            text = case status
                   when :scanning then "#{UIConstants::COLOR_TEXT_WARNING}⟳ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                   when :error then "#{UIConstants::COLOR_TEXT_ERROR}✗ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                   when :done then "#{UIConstants::COLOR_TEXT_SUCCESS}✓ #{@scanner.scan_message || ''}#{Terminal::ANSI::RESET}"
                   else ''
                   end
            surface.write(bounds, 4, 2, text) unless text.empty?
          end

          # List or empty state
          if @filtered_epubs.nil? || @filtered_epubs.empty?
            empty_text = if status == :scanning
                           "#{UIConstants::COLOR_TEXT_WARNING}⟳ Scanning for books...#{Terminal::ANSI::RESET}"
                         else
                           "#{UIConstants::COLOR_TEXT_DIM}No matching books#{Terminal::ANSI::RESET}"
                         end
            surface.write(bounds, height / 2, [(width - 20) / 2, 1].max, empty_text)
          else
            render_list(surface, bounds, height, width)
          end

          hint = "#{@filtered_epubs&.length.to_i} books • #{BROWSE_FOOTER_HINTS}"
          surface.write(bounds, height - 1, [(width - hint.length) / 2, 1].max,
                        UIConstants::COLOR_TEXT_DIM + hint + Terminal::ANSI::RESET)
        end

        private

        def renderer = nil

        def calculate_visible_range(list_height)
          start = 0
          start = @selected - list_height + 1 if @selected >= list_height
          if @filtered_epubs.length > list_height
            start = [start,
                     @filtered_epubs.length - list_height].min
          end
          start = [start, 0].max

          visible_end = [start + list_height, @filtered_epubs.length].min
          start...visible_end
        end

        def render_list(surface, bounds, height, width)
          list_start = 6
          list_height = [height - 8, 1].max
          range = calculate_visible_range(list_height)

          range.each_with_index do |idx, row|
            break if row >= list_height

            book = @filtered_epubs[idx]
            next unless book

            name = (book['name'] || 'Unknown')[0, [width - 40, 40].max]
            row_y = list_start + row
            if idx == @selected
              surface.write(bounds, row_y, 2,
                            UIConstants::SELECTION_POINTER_COLOR + UIConstants::SELECTION_POINTER + Terminal::ANSI::RESET)
              surface.write(bounds, row_y, 4, UIConstants::SELECTION_HIGHLIGHT + name + Terminal::ANSI::RESET)
            else
              surface.write(bounds, row_y, 2, '  ')
              surface.write(bounds, row_y, 4, UIConstants::COLOR_TEXT_PRIMARY + name + Terminal::ANSI::RESET)
            end

            next unless width > 60

            path = (book['dir'] || '').sub(Dir.home, '~')
            path = "#{path[0, 30]}..." if path.length > 33
            surface.write(bounds, row_y, [width - 35, 45].max,
                          UIConstants::COLOR_TEXT_DIM + path + Terminal::ANSI::RESET)
          end

          return unless @filtered_epubs.length > list_height

          denominator = [@filtered_epubs.length - 1, 1].max
          scroll_pos = @filtered_epubs.length > 1 ? @selected.to_f / denominator : 0
          scroll_row = list_start + (scroll_pos * (list_height - 1)).to_i
          surface.write(bounds, scroll_row, width - 1,
                        "#{UIConstants::SELECTION_POINTER_COLOR}█#{Terminal::ANSI::RESET}")
        end

        # Rendering logic handled by MainMenuRenderer
      end
    end
  end
end
require_relative '../../components/surface'
require_relative '../../components/rect'
