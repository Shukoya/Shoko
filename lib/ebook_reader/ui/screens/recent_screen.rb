# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Screen that lists recently opened books and allows
      # quick navigation back to them.
      class RecentScreen
        attr_accessor :selected

        RenderContext = Struct.new(:recent_files, :params, :height, :width)
        private_constant :RenderContext

        def initialize(menu, renderer = nil)
          @menu = menu
          @selected = 0
          @renderer = renderer
        end

        def draw(height, width)
          recent = load_recent_books
          renderer.render_recent_screen(
            UI::MainMenuRenderer::RecentContext.new(
              height: height, width: width, items: recent, selected: @selected, menu: @menu
            )
          )
        end

        private

        def renderer
          @renderer ||= UI::MainMenuRenderer.new(@menu.instance_variable_get(:@config))
        end

        def load_recent_books
          recent = RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          @selected = 0 if @selected >= recent.length
          recent
        end

        # Rendering delegated to MainMenuRenderer
      end
    end
  end
end
