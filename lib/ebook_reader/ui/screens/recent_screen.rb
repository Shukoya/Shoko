# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../components/surface'
require_relative '../../components/rect'
require_relative '../../components/screens/recent_screen_component'
require 'time'

module EbookReader
  module UI
    module Screens
      # Screen that lists recently opened books and allows
      # quick navigation back to them.
      class RecentScreen
        include EbookReader::Constants

        attr_accessor :selected

        RenderContext = Struct.new(:recent_files, :params, :height, :width)
        private_constant :RenderContext

        def initialize(menu, _renderer = nil)
          @menu = menu
          @selected = 0
          @component = EbookReader::Components::Screens::RecentScreenComponent.new
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)

          context = {
            selected: @selected,
            menu: @menu,
          }

          @component.render(surface, bounds, context)
        end

        def load_recent_books
          recent = RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          @selected = 0 if @selected >= recent.length
          recent
        end
      end
    end
  end
end
