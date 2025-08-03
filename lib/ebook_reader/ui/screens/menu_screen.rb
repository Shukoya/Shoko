# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Displays the main application menu and delegates rendering of
      # individual menu items to a renderer object.
      class MenuScreen
        attr_accessor :selected

        def initialize(renderer, selected)
          @renderer = renderer
          @selected = selected
        end

        def draw(height, width)
          menu_start = @renderer.render_logo(height, width)
          menu_items = build_menu_items
          render_menu_items(MenuRenderContext.new(items: menu_items,
                                                  start_row: menu_start,
                                                  height: height,
                                                  width: width))
          @renderer.render_footer(height, width,
                                  'Navigate with ↑↓ or jk • Select with Enter')
        end

        private

        def build_menu_items
          [
            { key: 'f', icon: '', text: 'Find Book', desc: 'Browse all EPUBs' },
            { key: 'r', icon: '󰁯', text: 'Recent', desc: 'Recently opened books' },
            { key: 'o', icon: '󰷏', text: 'Open File', desc: 'Enter path manually' },
            { key: 's', icon: '', text: 'Settings', desc: 'Configure reader' },
            { key: 'q', icon: '󰿅', text: 'Quit', desc: 'Exit application' },
          ]
        end

        MenuRenderContext = Struct.new(:items, :start_row, :height, :width,
                                       keyword_init: true)

        def render_menu_items(context)
          context.items.each_with_index do |item, i|
            row = context.start_row + (i * 2)
            next if row >= context.height - 2

            pointer_col = [(context.width / 2) - 20, 2].max
            text_col = [(context.width / 2) - 18, 4].max

            @renderer.render_menu_item(UI::MainMenuRenderer::MenuItemContext.new(
                                         row: row,
                                         pointer_col: pointer_col,
                                         text_col: text_col,
                                         item: item,
                                         selected: i == @selected
                                       ))
          end
        end
      end
    end
  end
end
