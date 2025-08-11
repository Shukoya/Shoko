# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../components/screens/menu_screen_component'

module EbookReader
  module UI
    module Screens
      # Displays the main application menu and delegates rendering of
      # individual menu items to a renderer object.
      class MenuScreen
        include EbookReader::Constants

        attr_accessor :selected

        MenuRenderContext = Struct.new(:items, :start_row, :height, :width, keyword_init: true)
        MenuItemContext = Struct.new(:row, :pointer_col, :text_col, :item, :selected,
                                     keyword_init: true)
        private_constant :MenuRenderContext
        private_constant :MenuItemContext

        def initialize(_renderer, selected)
          @selected = selected
          @component = EbookReader::Components::Screens::MenuScreenComponent.new
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)

          context = { selected: @selected }
          @component.render(surface, bounds, context)
        end
      end
    end
  end
end
