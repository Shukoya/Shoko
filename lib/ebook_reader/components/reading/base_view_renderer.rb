# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      # Base class for all view renderers
      class BaseViewRenderer
        attr_reader :services

        def initialize(services = nil)
          @services = services || Services::ServiceRegistry
          @needs_redraw = true
        end

        # Main rendering interface
        # @param surface [Surface] The rendering surface
        # @param bounds [Rect] The rendering bounds
        # @param controller [ReaderController] The controller instance
        def render(surface, bounds, controller)
          raise NotImplementedError, 'Subclasses must implement render method'
        end

        protected

        def layout_metrics(width, height, view_mode)
          @services.layout.calculate_metrics(width, height, view_mode)
        end

        def adjust_for_line_spacing(height, line_spacing)
          @services.layout.adjust_for_line_spacing(height, line_spacing)
        end

        def calculate_center_start_row(content_height, lines_count, line_spacing)
          @services.layout.calculate_center_start_row(content_height, lines_count, line_spacing)
        end

        def draw_line(surface, bounds, line:, row:, col:, width:, controller:)
          text = line.to_s[0, width]
          config = controller.config

          if config.respond_to?(:highlight_keywords) && config.highlight_keywords
            text = highlight_keywords(text)
          end
          text = highlight_quotes(text) if config.highlight_quotes

          abs_row = bounds.y + row - 1
          abs_col = bounds.x + col - 1
          
          # Store line data in format compatible with mouse selection
          # Use a key that includes column position to avoid overwrites
          controller.state.rendered_lines ||= {}
          line_key = "#{abs_row}_#{abs_col}"
          controller.state.rendered_lines[line_key] = {
            row: abs_row,
            col: abs_col,
            text: text,
            width: width
          }

          surface.write(bounds, row, col, Terminal::ANSI::WHITE + text + Terminal::ANSI::RESET)
        end

        def highlight_keywords(line)
          line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
            Terminal::ANSI::CYAN + match + Terminal::ANSI::WHITE
          end
        end

        def highlight_quotes(line)
          line.gsub(Constants::QUOTE_PATTERNS) do |match|
            Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + Terminal::ANSI::WHITE
          end
        end
      end
    end
  end
end
