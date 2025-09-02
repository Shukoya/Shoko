# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Open file dialog component
      class OpenFileScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(state)
          super()
          @state = state
        end

        def input=(value)
          @state.set(%i[menu file_input], value || '')
        end

        def input
          @state.get(%i[menu file_input]) || ''
        end

        def do_render(surface, bounds)
          height = bounds.height
          width = bounds.width

          # Header
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}📂 Open File#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, width - 20, "#{COLOR_TEXT_DIM}[ESC] Cancel#{Terminal::ANSI::RESET}")

          # File path input
          surface.write(bounds, 3, 2, "#{COLOR_TEXT_PRIMARY}File path:#{Terminal::ANSI::RESET}")

          # Input field with cursor
          input_text = @state.get(%i[menu file_input]) || ''
          input_width = [width - 15, 40].max
          display_input = truncate_input(input_text, input_width)

          surface.write(bounds, 4, 4, "#{SELECTION_HIGHLIGHT}#{display_input}█#{Terminal::ANSI::RESET}")

          # Instructions
          surface.write(bounds, 6, 2, "#{COLOR_TEXT_DIM}Enter the path to an EPUB file#{Terminal::ANSI::RESET}")
          surface.write(bounds, 7, 2,
                        "#{COLOR_TEXT_DIM}Supports ~ for home directory and tab completion#{Terminal::ANSI::RESET}")

          # Controls
          surface.write(bounds, height - 3, 2, "#{COLOR_TEXT_DIM}[Enter] Open file#{Terminal::ANSI::RESET}")
          surface.write(bounds, height - 2, 2, "#{COLOR_TEXT_DIM}[ESC] Cancel#{Terminal::ANSI::RESET}")
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def truncate_input(text, max_width)
          return text if text.length <= max_width

          # Show end of path if too long
          excess = text.length - max_width + 3
          "...#{text[excess..]}"
        end
      end
    end
  end
end
