# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Component-based renderer for the main menu screen
      class MenuScreenComponent < BaseScreenComponent
        include EbookReader::Constants

        MENU_ITEMS = [
          { key: 'f', label: 'Browse Library',
            description: 'Find and open books from your collection' },
          { key: 'r', label: 'Recent Books', description: 'Quickly access recently opened books' },
          { key: 'a', label: 'Annotations', description: 'View and manage your annotations' },
          { key: 'o', label: 'Open File', description: 'Open an EPUB file directly' },
          { key: 's', label: 'Settings', description: 'Customize reader preferences' },
          { key: 'q', label: 'Quit', description: 'Exit the application' },
        ].freeze

        def render(surface, bounds, context)
          selected = context[:selected] || 0

          render_header(surface, bounds)
          render_menu_items(surface, bounds, selected)
          render_footer(surface, bounds)
        end

        private

        def render_header(surface, bounds)
          title = "#{UIConstants::COLOR_TEXT_ACCENT}📚 EBook Reader#{Terminal::ANSI::RESET}"
          write_header(surface, bounds, title)
        end

        def render_menu_items(surface, bounds, selected)
          start_row = [(bounds.height - (MENU_ITEMS.size * 3)) / 2, 4].max

          MENU_ITEMS.each_with_index do |item, index|
            row = start_row + (index * 3)
            next if row >= bounds.height - 4

            render_menu_item(surface, bounds, row, item, index, selected)
          end
        end

        def render_menu_item(surface, bounds, row, item, index, selected)
          is_selected = (index == selected)
          indent = (bounds.width - 60) / 2

          # Selection indicator and key
          if is_selected
            surface.write(bounds, row, indent,
                          "#{UIConstants::SELECTION_HIGHLIGHT}▸ [#{item[:key]}]#{Terminal::ANSI::RESET}")
            surface.write(bounds, row, indent + 6,
                          "#{UIConstants::SELECTION_HIGHLIGHT}#{item[:label]}#{Terminal::ANSI::RESET}")
          else
            surface.write(bounds, row, indent, "#{UIConstants::COLOR_TEXT_DIM}  [#{item[:key]}]#{Terminal::ANSI::RESET}")
            surface.write(bounds, row, indent + 6,
                          "#{UIConstants::COLOR_TEXT_PRIMARY}#{item[:label]}#{Terminal::ANSI::RESET}")
          end

          # Description
          surface.write(bounds, row + 1, indent + 2,
                        "#{UIConstants::COLOR_TEXT_DIM}#{item[:description]}#{Terminal::ANSI::RESET}")
        end

        def render_footer(surface, bounds)
          write_footer(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Select • [key] Direct access#{Terminal::ANSI::RESET}"
          )
        end
      end
    end
  end
end
