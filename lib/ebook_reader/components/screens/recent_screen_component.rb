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

        def render(surface, bounds, context)
          items = load_recent_books
          selected = context[:selected] || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty_state(surface, bounds)
          else
            render_recent_list(surface, bounds, items, selected, context[:menu])
          end

          render_footer(surface, bounds)
        end

        private

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
          max_items = [(bounds.height - 6) / 2, 10].min

          items.take(max_items).each_with_index do |book, i|
            row_base = list_start + (i * 2)
            next if row_base >= bounds.height - 2

            render_recent_item(surface, bounds, row_base, bounds.width, book, i, selected, menu)
          end
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
