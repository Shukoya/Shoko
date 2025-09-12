# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Screens
      # Simple progress/loading overlay rendered as a component.
      # Draws a single-row progress bar; expects progress in state at [:ui, :loading_progress].
      class LoadingOverlayComponent < BaseComponent
        include Constants::UIConstants

        def do_render(surface, bounds)
          width  = bounds.width
          height = bounds.height

          bar_row = [2, height - 1].min
          bar_col = 2
          bar_width = (width - (bar_col + 1)).clamp(10, width - bar_col)

          progress = (@dependencies.resolve(:global_state).get(%i[ui loading_progress]) || 0.0).to_f
          progress = progress.clamp(0.0, 1.0)
          filled = (bar_width * progress).round

          track = if bar_width.positive?
                    (Terminal::ANSI::BRIGHT_GREEN + ('━' * filled)) +
                      (Terminal::ANSI::GRAY + ('━' * (bar_width - filled))) +
                      Terminal::ANSI::RESET
                  else
                    ''
                  end
          surface.write(bounds, bar_row, bar_col, track)
        end
      end
    end
  end
end
