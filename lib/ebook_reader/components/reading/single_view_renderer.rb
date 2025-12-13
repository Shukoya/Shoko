# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for single-view reading mode (supports both dynamic and absolute page numbering)
      class SingleViewRenderer < BaseViewRenderer
        def initialize(dependencies, page_numbering_mode: :dynamic)
          super(dependencies)
          @page_numbering_mode = page_numbering_mode
        end

        def render_with_context(surface, bounds, context)
          if context.page_numbering_mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        def render_dynamic_lines(surface, bounds, lines, params)
          draw_lines(surface, bounds, lines, params)
        end

        def render_absolute_lines(surface, bounds, lines, params)
          draw_lines(surface, bounds, lines, params)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_calculator = context.page_calculator
          st = context&.state
          col_width, content_height, spacing, displayable = compute_layout(bounds, :single,
                                                                           context.config)
          col_start = center_start_col(bounds.width, col_width)

          if page_calculator && (pd = page_calculator.get_page(context.current_page_index))
            start_line = pd[:start_line].to_i
            end_line = pd[:end_line].to_i
            span_length = end_line - start_line + 1
            span_length = [span_length, displayable].max
            chapter_index = (pd[:chapter_index] || st&.get(%i[reader current_chapter]) || 0).to_i

            dyn_lines = pd[:lines]
            if dyn_lines.nil? || dyn_lines.empty?
              dyn_lines, start_line = fetch_wrapped_lines_with_offset(context.document, chapter_index, col_width,
                                                                      start_line, span_length)
            else
              snapped_start = snap_offset_to_image_start(dyn_lines, start_line)
              if snapped_start != start_line
                dyn_lines, start_line = fetch_wrapped_lines_with_offset(context.document, chapter_index, col_width,
                                                                        snapped_start, span_length)
              end
            end
            start_row = calculate_center_start_row(content_height, dyn_lines.size, spacing)
            params = Models::RenderParams.new(start_row: start_row, col_start: col_start,
                                              col_width: col_width, context: context,
                                              line_offset: start_line,
                                              page_id: context.current_page_index,
                                              column_id: 0)
            render_dynamic_lines(surface, bounds, dyn_lines, params)
            return
          end

          # Fallback when dynamic map not ready yet: use pending precise line_offset if available
          offset = compute_dynamic_offset(context, displayable)
          chapter_index = st.get(%i[reader current_chapter]) || 0 if st
          chapter_index ||= 0
          lines, offset = fetch_wrapped_lines_with_offset(context.document, chapter_index, col_width, offset,
                                                          displayable)
          start_row = calculate_center_start_row(content_height, lines.size, spacing)
          params = Models::RenderParams.new(start_row: start_row, col_start: col_start,
                                            col_width: col_width, context: context,
                                            line_offset: offset,
                                            page_id: context.current_page_index,
                                            column_id: 0)
          render_dynamic_lines(surface, bounds, lines, params)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height, spacing, displayable = compute_layout(bounds, :single,
                                                                           context.config)
          col_start = center_start_col(bounds.width, col_width)

          st = context&.state
          return unless st

          offset = st.get(%i[reader single_page]) || 0
          chapter_index = st.get(%i[reader current_chapter]) || 0
          lines, offset = fetch_wrapped_lines_with_offset(context.document, chapter_index, col_width, offset,
                                                          displayable)
          start_row = calculate_center_start_row(content_height, lines.size, spacing)

          params = Models::RenderParams.new(start_row: start_row, col_start: col_start,
                                            col_width: col_width, context: context,
                                            line_offset: offset,
                                            page_id: context.current_page_index,
                                            column_id: 0)
          render_absolute_lines(surface, bounds, lines, params)
        end

        def compute_dynamic_offset(context, displayable)
          pending = context.state.get(%i[reader pending_progress]) if context&.state
          line_offset = pending && (pending[:line_offset] || pending['line_offset'])
          return line_offset.to_i if line_offset

          (context.current_page_index || 0) * [displayable, 1].max
        end

        # helpers provided by BaseViewRenderer
      end
    end
  end
end
