# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../helpers/text_metrics'

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
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(file_input: value || ''))
        end

        def input
          @state.get(%i[menu file_input]) || ''
        end

        def do_render(surface, bounds)
          height = bounds.height
          width = bounds.width

          # Header
          reset = Terminal::ANSI::RESET
          title_plain = '📂 Open File'
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}#{title_plain}#{reset}")

          cancel_plain = '[ESC] Cancel'
          cancel_width = EbookReader::Helpers::TextMetrics.visible_length(cancel_plain)
          cancel_col = [width - cancel_width - 1,
                        2 + EbookReader::Helpers::TextMetrics.visible_length(title_plain) + 2].max
          surface.write(bounds, 1, cancel_col, "#{COLOR_TEXT_DIM}#{cancel_plain}#{reset}")

          # File path input
          surface.write(bounds, 3, 2, "#{COLOR_TEXT_PRIMARY}File path:#{Terminal::ANSI::RESET}")

          # Input field with cursor
          input_text = @state.get(%i[menu file_input]) || ''
          available = [width - 4, 1].max
          desired = [width - 15, 40].max
          input_width = [desired, available].min
          display_input = truncate_input(input_text, input_width)

          surface.write(bounds, 4, 4, "#{SELECTION_HIGHLIGHT}#{display_input}█#{reset}")

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
          w = max_width.to_i
          return '' if w <= 0

          str = text.to_s
          return str if EbookReader::Helpers::TextMetrics.visible_length(str) <= w
          return EbookReader::Helpers::TextMetrics.truncate_to(str, w) if w <= 3

          tail_width = w - 3
          "...#{take_last_cells(str, tail_width)}"
        end

        def take_last_cells(text, width)
          target = width.to_i
          return '' if target <= 0

          clusters = text.to_s.scan(/\X/)
          consumed = 0
          out = []

          clusters.reverse_each do |cluster|
            cw = EbookReader::Helpers::TextMetrics.display_width_for(cluster)
            next if cw <= 0
            break if consumed + cw > target

            out << cluster
            consumed += cw
          end

          out.reverse.join
        end
      end
    end
  end
end
