# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Displays the main application menu and delegates rendering of
      # individual menu items to a renderer object.
      class MenuScreen
        attr_accessor :selected

        MenuRenderContext = Struct.new(:items, :start_row, :height, :width, keyword_init: true)
        MenuItemContext = Struct.new(:row, :pointer_col, :text_col, :item, :selected, keyword_init: true)
        private_constant :MenuRenderContext
        private_constant :MenuItemContext

        def initialize(_renderer, selected)
          @selected = selected
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)

          # Simple header/logo area
          title = 'Reader'
          logo_row = [2, 1].max
          col = [(width - title.length) / 2, 1].max
          surface.write(bounds, logo_row, col, Terminal::ANSI::BRIGHT_CYAN + title + Terminal::ANSI::RESET)

          menu_start = logo_row + 4
          menu_items = build_menu_items
          render_menu_items(MenuRenderContext.new(items: menu_items,
                                                  start_row: menu_start,
                                                  height: height,
                                                  width: width,
                                                 ))

          footer = 'Navigate with ↑↓ or jk • Select with Enter'
          surface.write(bounds, height - 1, [(width - footer.length) / 2, 1].max,
                        Terminal::ANSI::DIM + Terminal::ANSI::WHITE + footer + Terminal::ANSI::RESET)
        end

        private

        def build_menu_items
          [
            { key: 'f', icon: '', text: 'Find Book', desc: 'Browse all EPUBs' },
            { key: 'r', icon: '󰁯', text: 'Recent', desc: 'Recently opened books' },
            { key: 'a', icon: '󰠮', text: 'Annotations', desc: 'View all annotations' },
            { key: 'o', icon: '󰷏', text: 'Open File', desc: 'Enter path manually' },
            { key: 's', icon: '', text: 'Settings', desc: 'Configure reader' },
            { key: 'q', icon: '󰿅', text: 'Quit', desc: 'Exit application' },
          ]
        end

        def render_menu_items(context)
          return if menu_bounds_exceeded?(context)

          context.items.each_with_index do |item, i|
            render_item_if_visible(item, i, context)
          end
        end

        def menu_bounds_exceeded?(context)
          context.start_row >= context.height - 2
        end

        def render_item_if_visible(item, index, context)
          item_context = build_item_context(item, index, context)
          return if item_context.row >= context.height - 2

          draw_menu_item(item_context)
        end

        def calculate_item_row(start_row, index)
          start_row + (index * 2)
        end

        def build_item_context(item, index, context)
          row = calculate_item_row(context.start_row, index)
          MenuItemContext.new(
            row: row,
            pointer_col: calculate_pointer_col(context.width),
            text_col: calculate_text_col(context.width),
            item: item,
            selected: index == @selected
          )
        end

        def calculate_pointer_col(width)
          [(width / 2) - 20, 2].max
        end

        def calculate_text_col(width)
          [(width / 2) - 18, 4].max
        end

        def draw_menu_item(context)
          pointer = context.selected ? Terminal::ANSI::BRIGHT_GREEN + '▸ ' + Terminal::ANSI::RESET : '  '
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: context.text_col + 60, height: context.row + 1)
          surface.write(bounds, context.row, context.pointer_col, pointer)

          item = context.item
          text = "#{item[:icon]}  #{item[:text]}"
          desc = item[:desc]
          name_color = context.selected ? Terminal::ANSI::BRIGHT_WHITE : Terminal::ANSI::WHITE
          desc_color = Terminal::ANSI::DIM + Terminal::ANSI::GRAY
          surface.write(bounds, context.row, context.text_col, name_color + text + Terminal::ANSI::RESET)
          surface.write(bounds, context.row, context.text_col + text.length + 2,
                        desc_color + desc.to_s + Terminal::ANSI::RESET)
        end
      end
    end
  end
end
