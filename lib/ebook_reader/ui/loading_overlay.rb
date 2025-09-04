# frozen_string_literal: true

module EbookReader
  module UI
    # Minimal progress overlay drawn at the top of the screen
    module LoadingOverlay
      module_function

      def render(terminal_service, state, message: 'Opening…')
        height, width = terminal_service.size
        terminal_service.start_frame
        surface = terminal_service.create_surface
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)

        # Single-row progress bar
        bar_row = [2, height - 1].min
        bar_col = 2
        bar_width = [[width - (bar_col + 1), 10].max, width - bar_col].min

        progress = (state.get(%i[ui loading_progress]) || 0.0).to_f.clamp(0.0, 1.0)
        filled = (bar_width * progress).round

        green_fg = Terminal::ANSI::BRIGHT_GREEN
        grey_fg  = Terminal::ANSI::GRAY
        reset    = Terminal::ANSI::RESET

        track = if bar_width.positive?
                  (green_fg + ('━' * filled)) + (grey_fg + ('━' * (bar_width - filled))) + reset
                else
                  ''
                end
        surface.write(bounds, bar_row, bar_col, track)

        terminal_service.end_frame
      end
    end
  end
end
