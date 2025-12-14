# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../render_style'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        LEFT_MARGIN = EbookReader::Domain::Services::LayoutService::SPLIT_LEFT_MARGIN
        RIGHT_MARGIN = EbookReader::Domain::Services::LayoutService::SPLIT_RIGHT_MARGIN
        COLUMN_GAP = EbookReader::Domain::Services::LayoutService::SPLIT_COLUMN_GAP

        def render_with_context(surface, bounds, context)
          if context.page_numbering_mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        # Divider provided by BaseViewRenderer#draw_divider

        def render_column_lines(surface, bounds, lines, start_col, col_width, context = nil,
                                column_id: 0, line_offset: 0, page_id: nil)
          params = Models::RenderParams.new(start_row: 3, col_start: start_col,
                                            col_width: col_width, context: context,
                                            column_id: column_id, line_offset: line_offset,
                                            page_id: page_id)
          draw_lines(surface, bounds, lines, params)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_calculator = context.page_calculator
          layout = split_layout(bounds, context.config)
          col_width = layout[:col_width]
          displayable = layout[:displayable]
          left_start = layout[:left_start]
          right_start = layout[:right_start]
          divider_param = layout[:divider_param]

          chapter = context.current_chapter
          render_chapter_header_with_context(surface, bounds, context.state, chapter) if chapter

          idx = context.current_page_index
          if page_calculator && (left_pd = page_calculator.get_page(idx))
            render_dynamic_from_page_data(surface, bounds, context, col_width, left_start,
                                          right_start, divider_param, left_pd,
                                          page_calculator.get_page(idx + 1))
            return
          end

          # Fallback when dynamic map not ready yet
          base_offset = (idx || 0) * [displayable, 1].max
          render_dynamic_fallback(surface, bounds, context, col_width, left_start,
                                  right_start, divider_param, base_offset, displayable)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          layout = split_layout(bounds, context.config)
          col_width = layout[:col_width]
          display_height = layout[:displayable]
          left_start = layout[:left_start]
          right_start = layout[:right_start]
          divider_param = layout[:divider_param]

          st = context&.state
          return unless st

          left_offset  = st.get(%i[reader left_page]) || 0
          right_offset = st.get(%i[reader right_page]) || display_height

          # Render components
          render_chapter_header_with_context(surface, bounds, st, chapter)
          col = ColumnContext.new(col_width: col_width, display_height: display_height,
                                  left_offset: left_offset, right_offset: right_offset,
                                  left_start: left_start, right_start: right_start,
                                  divider_param: divider_param)
          render_absolute_columns(surface, bounds, context, col)
        end

        def render_chapter_header_with_context(surface, bounds, st, chapter)
          idx = st.get(%i[reader current_chapter]) + 1
          info = "[#{idx}] #{chapter.title || 'Unknown'}"
          reset = Terminal::ANSI::RESET
          available = bounds.width - LEFT_MARGIN - RIGHT_MARGIN
          heading_color = EbookReader::Components::RenderStyle.color(:heading)
          header_col = LEFT_MARGIN + 1
          start_column = bounds.x + header_col - 2
          clipped = EbookReader::Helpers::TextMetrics.truncate_to(info, available, start_column: start_column)
          surface.write(bounds, 1, header_col, heading_color + clipped + reset)
        end

        def render_dynamic_from_page_data(surface, bounds, context, col_width, left_start,
                                          right_start, divider_param, left_pd, right_pd)
          left_offset = left_pd[:start_line].to_i
          left_lines = left_pd[:lines]
          if left_lines.nil? || left_lines.empty?
            left_lines, left_offset = fetch_wrapped_lines_window(context, col_width, left_offset,
                                                                 page_span_length(left_pd))
          else
            snapped = snap_offset_to_image_start(left_lines, left_offset)
            if snapped != left_offset
              left_lines, left_offset = fetch_wrapped_lines_window(context, col_width, snapped,
                                                                   page_span_length(left_pd))
            end
          end
          render_column_lines(surface, bounds, left_lines, left_start, col_width, context,
                              column_id: 0, line_offset: left_offset,
                              page_id: context.current_page_index)
          draw_divider(surface, bounds, divider_param)
          return unless right_pd

          right_offset = right_pd[:start_line].to_i
          right_lines = right_pd[:lines]
          if right_lines.nil? || right_lines.empty?
            right_lines, right_offset = fetch_wrapped_lines_window(context, col_width, right_offset,
                                                                   page_span_length(right_pd))
          else
            snapped = snap_offset_to_image_start(right_lines, right_offset)
            if snapped != right_offset
              right_lines, right_offset = fetch_wrapped_lines_window(context, col_width, snapped,
                                                                     page_span_length(right_pd))
            end
          end
          render_column_lines(surface, bounds, right_lines, right_start, col_width, context,
                              column_id: 1, line_offset: right_offset,
                              page_id: context.current_page_index ? context.current_page_index + 1 : nil)
        end

        def render_dynamic_fallback(surface, bounds, context, col_width, left_start,
                                    right_start, divider_param, base_offset, displayable)
          left_lines, left_offset = fetch_wrapped_lines_window(context, col_width, base_offset, displayable)
          render_column_lines(surface, bounds, left_lines, left_start, col_width, context,
                              column_id: 0, line_offset: left_offset,
                              page_id: context.current_page_index)
          draw_divider(surface, bounds, divider_param)
          right_base_offset = base_offset + displayable
          right_lines, right_offset = fetch_wrapped_lines_window(context, col_width, right_base_offset, displayable)
          render_column_lines(surface, bounds, right_lines, right_start, col_width, context,
                              column_id: 1, line_offset: right_offset,
                              page_id: context.current_page_index ? context.current_page_index + 1 : nil)
        end

        ColumnContext = Struct.new(:col_width, :display_height, :left_offset, :right_offset,
                                   :left_start, :right_start, :divider_param, keyword_init: true)

        def render_absolute_columns(surface, bounds, context, col)
          cw = col.col_width
          dh = col.display_height

          paired = col.right_offset.to_i == col.left_offset.to_i + dh
          left_lines, left_offset = fetch_wrapped_lines_window(context, cw, col.left_offset, dh)
          render_column_lines(surface, bounds, left_lines, col.left_start, cw, context,
                              column_id: 0, line_offset: left_offset,
                              page_id: context.current_page_index)
          draw_divider(surface, bounds, col.divider_param)

          right_input = paired ? left_offset + dh : col.right_offset
          right_lines, right_offset = fetch_wrapped_lines_window(context, cw, right_input, dh)
          render_column_lines(surface, bounds, right_lines, col.right_start, cw, context,
                              column_id: 1, line_offset: right_offset,
                              page_id: context.current_page_index)
        end

        def fetch_wrapped_lines_window(context, col_width, offset, length)
          st = context.state
          chapter_index = st.get(%i[reader current_chapter]) || 0
          fetch_wrapped_lines_with_offset(context.document, chapter_index, col_width, offset, length)
        end

        def page_span_length(page_data)
          start_line = page_data[:start_line].to_i
          end_line = page_data[:end_line].to_i
          span = end_line - start_line + 1
          [span, 1].max
        end

        def split_layout(bounds, config)
          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          spacing = resolve_line_spacing(config)
          displayable = adjust_for_line_spacing(content_height, spacing)

          left_start = LEFT_MARGIN + 1
          right_start = left_start + col_width + COLUMN_GAP
          divider_col = left_start + col_width + 1

          {
            col_width: col_width,
            content_height: content_height,
            spacing: spacing,
            displayable: displayable,
            left_start: left_start,
            right_start: right_start,
            divider_param: divider_col,
          }
        end
      end
    end
  end
end
