# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../components/surface'
require_relative '../../components/rect'

module EbookReader
  module UI
    module Screens
      # Screen for entering a file path to open an EPUB.
      class OpenFileScreen
        include EbookReader::Constants

        attr_accessor :input

        def initialize(_renderer = nil)
          @input = ''
          @renderer = nil
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          surface.write(bounds, 1, 2, "#{UIConstants::COLOR_TEXT_ACCENT}󰷏 Open File#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [width - 20, 60].max,
                        "#{UIConstants::COLOR_TEXT_DIM}[ESC] Cancel#{Terminal::ANSI::RESET}")
          prompt = 'Enter EPUB path: '
          col = [(width - prompt.length - 40) / 2, 2].max
          row = height / 2
          surface.write(bounds, row, col, UIConstants::COLOR_TEXT_PRIMARY + prompt + Terminal::ANSI::RESET)
          surface.write(bounds, row, col + prompt.length,
                        "#{UIConstants::SELECTION_HIGHLIGHT}#{@input}_#{Terminal::ANSI::RESET}")
          footer = 'Enter to open • Backspace delete • ESC cancel'
          surface.write(bounds, height - 1, 2, UIConstants::COLOR_TEXT_DIM + footer + Terminal::ANSI::RESET)
        end

        private

        def renderer = nil
      end
    end
  end
end
