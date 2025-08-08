# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Screen for entering a file path to open an EPUB.
      class OpenFileScreen
        attr_accessor :input

        def initialize(renderer = nil)
          @input = ''
          @renderer = renderer
        end

        def draw(height, width)
          renderer.render_open_file_screen(
            UI::MainMenuRenderer::OpenFileContext.new(
              height: height, width: width, input: @input
            )
          )
        end

        private

        def renderer
          @renderer ||= UI::MainMenuRenderer.new(EbookReader::Config.new)
        end
      end
    end
  end
end
