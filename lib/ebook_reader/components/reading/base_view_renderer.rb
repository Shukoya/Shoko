# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../models/rendering_context'
require_relative '../../models/render_params'

module EbookReader
  module Components
    module Reading
      # Base class for all view renderers
      class BaseViewRenderer < BaseComponent
        def initialize(dependencies)
          super()
          @dependencies = dependencies
          unless @dependencies
            raise ArgumentError,
                  'Dependencies must be provided to BaseViewRenderer'
          end

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
            state&.dispatch(EbookReader::Domain::Actions::UpdateRenderedLinesAction.new(@rendered_lines_buffer))
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

        # Compute common layout values for a given view mode
        # Returns [col_width, content_height, spacing, displayable]
        def compute_layout(bounds, view_mode, config)
          col_width, content_height = layout_metrics(bounds.width, bounds.height, view_mode)
          spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(config)
          displayable = adjust_for_line_spacing(content_height, spacing)
          [col_width, content_height, spacing, displayable]
        end

        # Draw a vertical divider between columns (shared helper)
        def draw_divider(surface, bounds, col_width, start_row = 3)
          (start_row..[bounds.height - 1, start_row + 1].max).each do |row|
            surface.write(
              bounds,
              row,
              col_width + 3,
              "#{EbookReader::Constants::UIConstants::BORDER_PRIMARY}│#{Terminal::ANSI::RESET}"
            )
          end
        end

        # Shared helpers for common renderer patterns
        def center_start_col(total_width, col_width)
          [(total_width - col_width) / 2, 1].max
        end

        def fetch_wrapped_lines(document, chapter_index, col_width, offset, length)
          chapter = document&.get_chapter(chapter_index)
          if @dependencies&.registered?(:wrapping_service) && chapter
            ws = @dependencies.resolve(:wrapping_service)
            ws.wrap_window(chapter.lines || [], chapter_index, col_width, offset, length)
          else
            (chapter&.lines || [])[offset, length] || []
          end
        end

        # Shared helper to draw a list of lines with spacing and clipping considerations.
        # Computes row progression based on current line spacing and stops at bounds.
        def draw_lines(surface, bounds, lines, params)
          ctx = params.context
          spacing = ctx ? EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(ctx.config) : :normal
          lines.each_with_index do |line, idx|
            row = params.start_row + (spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 1

            draw_line(surface, bounds, line: line, row: row, col: params.col_start, width: params.col_width,
                                       context: ctx)
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
          text = styled_text_for(line, width, context)
          abs_row, abs_col = absolute_cell(bounds, row, col)
          record_rendered_line(abs_row, abs_col, width, text)
          surface.write(
            bounds,
            row,
            col,
            EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + text + Terminal::ANSI::RESET
          )
        end

        def styled_text_for(line, width, context)
          text = line.to_s[0, width]
          config = context&.config
          text = highlight_keywords(text) if config&.get(%i[config highlight_keywords])
          text = highlight_quotes(text) if config&.get(%i[config highlight_quotes])
          text
        end

        def absolute_cell(bounds, row, col)
          [bounds.y + row - 1, bounds.x + col - 1]
        end

        def record_rendered_line(abs_row, abs_col, width, text)
          return unless @rendered_lines_buffer.is_a?(Hash)

          end_col = abs_col + width - 1
          line_key = "#{abs_row}_#{abs_col}_#{end_col}"
          @rendered_lines_buffer[line_key] = {
            row: abs_row,
            col: abs_col,
            col_end: end_col,
            text: text,
            width: width,
          }
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
