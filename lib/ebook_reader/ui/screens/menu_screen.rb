# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Displays the main application menu and delegates rendering of
      # individual menu items to a renderer object.
      class MenuScreen
        attr_accessor :selected

        MenuRenderContext = Struct.new(:items, :start_row, :height, :width, keyword_init: true)
        private_constant :MenuRenderContext

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

          @renderer.render_menu_item(item_context)
        end

        def calculate_item_row(start_row, index)
          start_row + (index * 2)
        end

        def build_item_context(item, index, context)
          row = calculate_item_row(context.start_row, index)
          UI::MainMenuRenderer::MenuItemContext.new(
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
      end
    end
  end
end
