# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../models/rendering_context'

module EbookReader
  module Components
    module Reading
      # Base class for all view renderers
      class BaseViewRenderer < BaseComponent
        def initialize(dependencies)
          super()
          @dependencies = dependencies
          raise ArgumentError, 'Dependencies must be provided to BaseViewRenderer' unless @dependencies

          @layout_service = @dependencies.resolve(:layout_service)
        end

        # Standard ComponentInterface implementation
        def do_render(surface, bounds)
          context = create_rendering_context
          return unless context

          # Collect rendered lines for a single, consistent state update per frame
          @rendered_lines_buffer = {}
          render_with_context(surface, bounds, context)
          begin
            state = context.state
            state.dispatch(EbookReader::Domain::Actions::UpdateRenderedLinesAction.new(@rendered_lines_buffer)) if state
          rescue StandardError
            # best-effort; avoid crashing render on bookkeeping
          ensure
            @rendered_lines_buffer = nil
          end
        end

        # New rendering interface using context
        def render_with_context(surface, bounds, context)
          raise NotImplementedError, 'Subclasses must implement render_with_context method'
        end

        protected

        def layout_metrics(width, height, view_mode)
          @layout_service.calculate_metrics(width, height, view_mode)
        end

        def adjust_for_line_spacing(height, line_spacing = :normal)
          @layout_service.adjust_for_line_spacing(height, line_spacing)
        end

        def calculate_center_start_row(content_height, lines_count, line_spacing)
          @layout_service.calculate_center_start_row(content_height, lines_count, line_spacing)
        end

        # Shared helper to draw a list of lines with spacing and clipping considerations.
        # Computes row progression based on current line spacing and stops at bounds.
        def draw_lines(surface, bounds, lines, start_row, col_start, col_width, context)
          spacing = context ? EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config) : :normal
          lines.each_with_index do |line, idx|
            row = start_row + (spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 1

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width, context: context)
          end
        end

        private

        def create_rendering_context
          state = @dependencies.resolve(:global_state)
          Models::RenderingContext.new(
            document: safe_resolve(:document),
            page_calculator: safe_resolve(:page_calculator),
            state: state,
            config: state,
            view_model: nil
          )
        end

        def draw_line(surface, bounds, line:, row:, col:, width:, context:)
          text = line.to_s[0, width]
          config = context&.config

          text = highlight_keywords(text) if config&.get(%i[config highlight_keywords])
          text = highlight_quotes(text) if config&.get(%i[config highlight_quotes])

          abs_row = bounds.y + row - 1
          abs_col = bounds.x + col - 1

          # Store line data in format compatible with mouse selection
          # Use a key that includes both row and column range to distinguish columns
          # Buffer rendered lines locally; flushed once per frame in do_render
          if @rendered_lines_buffer.is_a?(Hash)
            line_key = "#{abs_row}_#{abs_col}_#{abs_col + width - 1}"
            @rendered_lines_buffer[line_key] = {
              row: abs_row,
              col: abs_col,
              col_end: abs_col + width - 1,
              text: text,
              width: width,
            }
          end

          surface.write(bounds, row, col,
                        EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + text + Terminal::ANSI::RESET)
        end

        def highlight_keywords(line)
          line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
            EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + match + EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY
          end
        end

        def highlight_quotes(line)
          line.gsub(Constants::QUOTE_PATTERNS) do |match|
            Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY
          end
        end

        def safe_resolve(name)
          return @dependencies.resolve(name) if @dependencies.registered?(name)
          nil
        end
      end
    end
  end
end
