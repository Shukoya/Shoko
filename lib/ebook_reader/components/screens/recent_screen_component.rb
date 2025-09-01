# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../../recent_files'
require 'time'

module EbookReader
  module Components
    module Screens
      # Component-based renderer for the recent books screen
      class RecentScreenComponent < BaseScreenComponent
        include EbookReader::Constants

        def initialize(main_menu, state)
          super()
          @main_menu = main_menu
          @state = state
        end

        # Setter method for selection index (used by input handlers)
        def selected=(index)
          @state.set(%i[menu browse_selected], index)
          invalidate
        end

        def do_render(surface, bounds)
          items = load_recent_books
          selected = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty_state(surface, bounds)
          else
            render_recent_list(surface, bounds, items, selected, @main_menu)
          end

          render_footer(surface, bounds)
        end

        private

        def load_recent_books
          @main_menu.send(:load_recent_books)
        end

        def render_header(surface, bounds)
          write_header(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_ACCENT}🕒 Recent Books#{Terminal::ANSI::RESET}",
            "#{UIConstants::COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}"
          )
        end

        def render_empty_state(surface, bounds)
          write_empty_message(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_DIM}No recent books#{Terminal::ANSI::RESET}"
          )
        end

        def render_recent_list(surface, bounds, items, selected, menu)
          list_start = 4
          # Number of item rows (each item takes 2 rows)
          visible_rows = bounds.height - list_start - 2
          items_per_page = [visible_rows / 2, 1].max

          start_index, visible_items = calculate_visible_range(items.length, items_per_page, selected)

          visible_items.each_with_index do |book, i|
            row_base = list_start + (i * 2)
            next if row_base >= bounds.height - 2

            render_recent_item(surface, bounds, row_base, bounds.width, book, start_index + i, selected, menu)
          end
        end

        def calculate_visible_range(total_items, per_page, selected)
          start_index = 0

          if selected >= per_page
            start_index = selected - per_page + 1
          end

          if total_items > per_page
            start_index = [start_index, total_items - per_page].min
          end

          end_index = [start_index + per_page - 1, total_items - 1].min
          [start_index, (load_recent_books[start_index..end_index] || [])]
        end

        def render_recent_item(surface, bounds, row, width, book, index, selected, menu)
          is_selected = (index == selected)

          # Book name
          if is_selected
            write_selection_pointer(surface, bounds, row, true)
            surface.write(bounds, row, 4,
                          UIConstants::SELECTION_HIGHLIGHT + (book['name'] || 'Unknown') + Terminal::ANSI::RESET)
          else
            write_selection_pointer(surface, bounds, row, false)
            surface.write(bounds, row, 4,
                          UIConstants::COLOR_TEXT_PRIMARY + (book['name'] || 'Unknown') + Terminal::ANSI::RESET)
          end

          # Time ago
          if book['accessed']
            time_ago = time_ago_in_words(Time.parse(book['accessed']), menu)
            surface.write(bounds, row, [width - 20, 60].max,
                          UIConstants::COLOR_TEXT_DIM + time_ago + Terminal::ANSI::RESET)
          end

          # File path
          return unless row + 1 < bounds.height - 2

          path = (book['path'] || '').sub(Dir.home, '~')
          surface.write(bounds, row + 1, 6,
                        UIConstants::COLOR_TEXT_DIM + path[0, width - 8] + Terminal::ANSI::RESET)
        end

        def render_footer(surface, bounds)
          write_footer(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}"
          )
        end

        def load_recent_books
          RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
        end

        def time_ago_in_words(time, menu)
          return 'unknown' unless time && menu.respond_to?(:time_ago_in_words)

          menu.time_ago_in_words(time)
        rescue StandardError
          'unknown'
        end
      end
    end
  end
end
