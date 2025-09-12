# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Component-based renderer for the main menu screen
      class MenuScreenComponent < BaseScreenComponent
        include EbookReader::Constants

        MenuItemCtx = Struct.new(:row, :item, :index, :selected, :indent, keyword_init: true)

        def initialize(state)
          super()
          @state = state
          @state.add_observer(self, %i[menu selected])
        end

        MENU_ITEMS = [
          { key: 'f', label: 'Browse Library',
            description: 'Find and open books from your collection' },
          { key: 'l', label: 'Library', description: 'Open cached/imported books instantly' },
          { key: 'a', label: 'Annotations', description: 'View and manage your annotations' },
          { key: 'o', label: 'Open File', description: 'Open an EPUB file directly' },
          { key: 's', label: 'Settings', description: 'Customize reader preferences' },
          { key: 'q', label: 'Quit', description: 'Exit the application' },
        ].freeze

        def do_render(surface, bounds)
          selected = EbookReader::Domain::Selectors::MenuSelectors.selected(@state) || 0

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
          b_height = bounds.height
          b_width  = bounds.width
          start_row = [(b_height - (MENU_ITEMS.size * 3)) / 2, 4].max
          indent = (b_width - 60) / 2

          MENU_ITEMS.each_with_index do |item, index|
            row = start_row + (index * 3)
            next if row >= b_height - 4

            ctx = MenuItemCtx.new(row: row, item: item, index: index, selected: selected, indent: indent)
            render_menu_item(surface, bounds, ctx)
          end
        end

        def render_menu_item(surface, bounds, ctx)
          ui = UIConstants
          reset = Terminal::ANSI::RESET
          item = ctx.item
          row = ctx.row
          is_selected = (ctx.index == ctx.selected)
          indent = ctx.indent

          # Selection indicator and key
          key_col = indent + 6
          key = item[:key]
          label = item[:label]
          if is_selected
            surface.write(bounds, row, indent,
                          "#{ui::SELECTION_HIGHLIGHT}▸ [#{key}]#{reset}")
            surface.write(bounds, row, key_col,
                          "#{ui::SELECTION_HIGHLIGHT}#{label}#{reset}")
          else
            surface.write(bounds, row, indent, "#{ui::COLOR_TEXT_DIM}  [#{key}]#{reset}")
            surface.write(bounds, row, key_col,
                          "#{ui::COLOR_TEXT_PRIMARY}#{label}#{reset}")
          end

          # Description
          surface.write(bounds, row + 1, indent + 2,
                        "#{ui::COLOR_TEXT_DIM}#{item[:description]}#{reset}")
        end

        def render_footer(surface, bounds)
          text = "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Select • [key] Direct access#{Terminal::ANSI::RESET}"
          write_footer(surface, bounds, text)
        end
      end
    end
  end
end
