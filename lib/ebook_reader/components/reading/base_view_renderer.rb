# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../models/rendering_context'
require_relative '../../services/layout_service'

module EbookReader
  module Components
    module Reading
      # Base class for all view renderers
      class BaseViewRenderer < BaseComponent
        def initialize(services = nil)
          super(services)
        end

        # Override the base render method to maintain legacy interface
        # @param surface [Surface] The rendering surface
        # @param bounds [Rect] The rendering bounds
        # @param controller [ReaderController] The controller instance
        def render(surface, bounds, controller = nil)
          if controller
            # Legacy interface - delegate to view_render
            view_render(surface, bounds, controller)
          else
            # New component interface
            super(surface, bounds)
          end
        end

        # Legacy rendering interface for backwards compatibility
        def view_render(surface, bounds, controller)
          # Create rendering context and delegate to new interface
          context = create_rendering_context(controller)
          render_with_context(surface, bounds, context)
        end

        # New rendering interface using context
        def render_with_context(surface, bounds, context)
          raise NotImplementedError, 'Subclasses must implement render_with_context method'
        end

        protected

        def layout_metrics(width, height, view_mode)
          Services::LayoutService.calculate_metrics(width, height, view_mode)
        end

        def adjust_for_line_spacing(height, line_spacing = :normal)
          Services::LayoutService.adjust_for_line_spacing(height, line_spacing)
        end

        def calculate_center_start_row(content_height, lines_count, line_spacing)
          Services::LayoutService.calculate_center_start_row(content_height, lines_count, line_spacing)
        end

        private

        def create_rendering_context(controller)
          Models::RenderingContext.new(
            document: controller.doc,
            page_manager: controller.page_manager,
            state: controller.state,
            config: controller.config,
            view_model: controller.create_view_model
          )
        end

        def draw_line(surface, bounds, line:, row:, col:, width:, controller: nil, context: nil)
          text = line.to_s[0, width]
          config = context ? context.config : controller&.config

          if config.respond_to?(:highlight_keywords) && config.highlight_keywords
            text = highlight_keywords(text)
          end
          text = highlight_quotes(text) if config.highlight_quotes

          abs_row = bounds.y + row - 1
          abs_col = bounds.x + col - 1
          
          # Store line data in format compatible with mouse selection
          # Use a key that includes both row and column range to distinguish columns
          state = context ? context.state : controller&.state
          if state
            state.rendered_lines ||= {}
            line_key = "#{abs_row}_#{abs_col}_#{abs_col + width - 1}"
            state.rendered_lines[line_key] = {
              row: abs_row,
              col: abs_col,
              col_end: abs_col + width - 1,
              text: text,
              width: width
            }
          end

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
