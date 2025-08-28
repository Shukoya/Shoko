# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Screens
      # Base component for all screen renderers
      class BaseScreenComponent < BaseComponent
        def initialize
          super
          @needs_redraw = true
        end

        # Screens typically take the full available height
        def preferred_height(available_height)
          available_height
        end

        protected

        def write_header(surface, bounds, title, help_text = nil)
          surface.write(bounds, 1, 2, title)
          return unless help_text

          surface.write(bounds, 1, [bounds.width - help_text.length - 2, bounds.width / 2].max,
                        help_text)
        end

        def write_footer(surface, bounds, text)
          surface.write(bounds, bounds.height - 1, 2, text)
        end

        def write_empty_message(surface, bounds, message)
          col = [(bounds.width - message.length) / 2, 1].max
          row = bounds.height / 2
          surface.write(bounds, row, col, message)
        end

        def write_selection_pointer(surface, bounds, row, selected = true)
          if selected
            surface.write(bounds, row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
          else
            surface.write(bounds, row, 2, '  ')
          end
        end
      end
    end
  end
end
