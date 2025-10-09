# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../models/rendering_context'
require_relative '../../models/render_params'
require_relative '../../models/line_geometry'
require_relative '../../helpers/text_metrics'
require_relative '../render_style'

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
          spacing = resolve_line_spacing(config)
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
          return [] unless chapter

          if @dependencies&.registered?(:formatting_service)
            begin
              formatting = @dependencies.resolve(:formatting_service)
              lines = formatting.wrap_window(document, chapter_index, col_width, offset, length)
              return lines unless lines.nil? || lines.empty?
            rescue StandardError
              # fall through to wrapping service fallback
            end
          end

          if @dependencies&.registered?(:wrapping_service)
            ws = @dependencies.resolve(:wrapping_service)
            return ws.wrap_window(chapter.lines || [], chapter_index, col_width, offset, length)
          end

          (chapter.lines || [])[offset, length] || []
        end

        # Shared helper to draw a list of lines with spacing and clipping considerations.
        # Computes row progression based on current line spacing and stops at bounds.
        def draw_lines(surface, bounds, lines, params)
          ctx = params.context
          spacing = ctx ? resolve_line_spacing(ctx.config) : :normal
          lines.each_with_index do |line, idx|
            row = params.start_row + (spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 1

            draw_line(surface, bounds,
                      line: line,
                      row: row,
                      col: params.col_start,
                      width: params.col_width,
                      context: ctx,
                      column_id: params.column_id,
                      line_offset: params.line_offset + idx,
                      page_id: params.page_id)
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

        def draw_line(surface, bounds, line:, row:, col:, width:, context:, column_id:, line_offset:,
                      page_id:)
          plain_text, styled_text = renderable_line_content(line, width, context)
          abs_row, abs_col = absolute_cell(bounds, row, col)
          geometry = build_line_geometry(page_id, column_id, abs_row, abs_col, line_offset,
                                         plain_text, styled_text)
          record_rendered_line(geometry)
          surface.write(bounds, row, col, styled_text)
        end

        def renderable_line_content(line, width, context)
          if line.respond_to?(:segments) && line.respond_to?(:text)
            plain, styled = styled_text_for_display_line(line, width)
            return [plain, styled]
          end

          text = line.to_s[0, width]
          if (store = config_store(context&.config))
            text = highlight_keywords(text) if store.get(%i[config highlight_keywords])
            text = highlight_quotes(text) if store.get(%i[config highlight_quotes])
          end
          styled = Components::RenderStyle.primary(text)
          [text, styled]
        end

        def absolute_cell(bounds, row, col)
          [bounds.y + row - 1, bounds.x + col - 1]
        end

        def record_rendered_line(geometry)
          return unless @rendered_lines_buffer.is_a?(Hash)

          width = geometry.visible_width
          return if width <= 0 && geometry.plain_text.empty?

          end_col = geometry.column_origin + width - 1
          line_key = geometry.key
          @rendered_lines_buffer[line_key] = {
            row: geometry.row,
            col: geometry.column_origin,
            col_end: end_col,
            text: geometry.plain_text,
            width: width,
            geometry: geometry,
          }

          dump_geometry(geometry) if geometry_debug_enabled?
        end

        def highlight_keywords(line)
          accent = Components::RenderStyle.color(:accent)
          base = Components::RenderStyle.color(:primary)
          line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
            accent + match + Terminal::ANSI::RESET + base
          end
        end

        def highlight_quotes(line)
          quote_color = Components::RenderStyle.color(:quote)
          base = Components::RenderStyle.color(:primary)
          line.gsub(Constants::QUOTE_PATTERNS) do |match|
            quote_color + Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + base
          end
        end

        def styled_text_for_display_line(line, width)
          metadata = line.metadata || {}
          plain_builder = +''
          styled_builder = +''
          remaining = width.to_i

          line.segments.each do |segment|
            break if remaining <= 0

            raw_text = segment.text.to_s
            next if raw_text.empty?

            visible_len = EbookReader::Helpers::TextMetrics.visible_length(raw_text)
            text_for_display = if visible_len > remaining
                                 EbookReader::Helpers::TextMetrics.truncate_to(raw_text, remaining)
                               else
                                 raw_text
                               end

            next if text_for_display.empty?

            plain_builder << text_for_display
            styled_builder << Components::RenderStyle.styled_segment(text_for_display,
                                                                     segment.styles || {},
                                                                     metadata: metadata)
            remaining -= EbookReader::Helpers::TextMetrics.visible_length(text_for_display)
          end

          if styled_builder.empty?
            plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
            return [plain_text, Components::RenderStyle.primary(plain_text)]
          end

          plain = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
          [plain, styled_builder]
        end

        def safe_resolve(name)
          return @dependencies.resolve(name) if @dependencies.registered?(name)

          nil
        end

        def resolve_line_spacing(config)
          store = config_store(config)
          if store
            EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(store)
          else
            :normal
          end
        rescue StandardError
          :normal
        end

        def config_store(config)
          return config if config.respond_to?(:get)
          return config.state if config.respond_to?(:state) && config.state.respond_to?(:get)

          nil
        end
      end
    end
  end
end
        def build_line_geometry(page_id, column_id, abs_row, abs_col, line_offset, plain_text, styled_text)
          cell_data = EbookReader::Helpers::TextMetrics.cell_data_for(plain_text)
          cells = cell_data.map do |cell|
            EbookReader::Models::LineCell.new(
              cluster: cell[:cluster],
              char_start: cell[:char_start],
              char_end: cell[:char_end],
              display_width: cell[:display_width],
              screen_x: cell[:screen_x]
            )
          end

          EbookReader::Models::LineGeometry.new(
            page_id: page_id,
            column_id: column_id,
            row: abs_row,
            column_origin: abs_col,
            line_offset: line_offset,
            plain_text: plain_text,
            styled_text: styled_text,
            cells: cells
          )
        end

        def geometry_debug_enabled?
          ENV['READER_DEBUG_GEOMETRY']&.to_s == '1'
        end

        def dump_geometry(geometry)
          logger = begin
            @dependencies.resolve(:logger)
          rescue StandardError
            nil
          end
          payload = geometry.to_h
          if logger
            logger.debug('geometry.line', payload)
          else
            warn("[geometry] #{payload}")
          end
        end
