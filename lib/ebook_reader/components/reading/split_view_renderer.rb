# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        def render_with_context(surface, bounds, context)
          if context.page_numbering_mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        # Divider provided by BaseViewRenderer#draw_divider

        def render_column_lines(surface, bounds, lines, start_col, col_width, context = nil)
          params = Models::RenderParams.new(start_row: 3, col_start: start_col,
                                            col_width: col_width, context: context)
          draw_lines(surface, bounds, lines, params)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_calculator = context.page_calculator
          col_width, _, _, displayable = compute_layout(bounds, :split,
                                                        context.config)

          chapter = context.current_chapter
          render_chapter_header_with_context(surface, bounds, context, chapter) if chapter

          idx = context.current_page_index
          if page_calculator && (left_pd = page_calculator.get_page(idx))
            render_dynamic_from_page_data(surface, bounds, context, col_width, left_pd,
                                          page_calculator.get_page(idx + 1))
            return
          end

          # Fallback when dynamic map not ready yet
          base_offset = (idx || 0) * [displayable, 1].max
          render_dynamic_fallback(surface, bounds, context, col_width, base_offset, displayable)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          bw = bounds.width
          bh = bounds.height
          col_width, content_height = layout_metrics(bw, bh, :split)
          spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config)
          display_height = adjust_for_line_spacing(content_height, spacing)

          st = context&.state
          return unless st
          left_offset  = st.get(%i[reader left_page]) || 0
          right_offset = st.get(%i[reader right_page]) || display_height

          # Render components
          render_chapter_header_with_context(surface, bounds, st, chapter)
          col = ColumnContext.new(col_width: col_width, display_height: display_height,
                                  left_offset: left_offset, right_offset: right_offset)
          render_absolute_columns(surface, bounds, context, col)
        end

        def render_chapter_header_with_context(surface, bounds, st, chapter)
          idx = st.get(%i[reader current_chapter]) + 1
          info = "[#{idx}] #{chapter.title || 'Unknown'}"
          reset = Terminal::ANSI::RESET
          surface.write(bounds, 1, 1,
                        EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + info[0, bounds.width - 2].to_s + reset)
        end

        def render_dynamic_left_column_with_context(surface, bounds, lines, col_width,
                                                    context)
          render_column_lines(surface, bounds, lines, 1, col_width, context)
        end

        def render_dynamic_right_column_with_context(surface, bounds, lines, col_width,
                                                     context)
          render_column_lines(surface, bounds, lines, col_width + 5, col_width, context)
        end

        def render_left_column_with_context(surface, bounds, wrapped, st, col_width,
                                            display_height)
          left_lines = wrapped.slice(st.get(%i[reader left_page]) || 0,
                                     display_height) || []
          render_column_lines(surface, bounds, left_lines, 1, col_width, nil)
        end

        def render_right_column_with_context(surface, bounds, wrapped, st, col_width,
                                             display_height)
          right_lines = wrapped.slice(st.get(%i[reader right_page]) || 0,
                                      display_height) || []
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width, nil)
        end

        def render_dynamic_from_page_data(surface, bounds, context, col_width, left_pd, right_pd)
          render_column_lines(surface, bounds, left_pd[:lines], 1, col_width, context)
          draw_divider(surface, bounds, col_width)
          return unless right_pd

          render_column_lines(surface, bounds, right_pd[:lines], col_width + 5, col_width, context)
        end

        def render_dynamic_fallback(surface, bounds, context, col_width, base_offset, displayable)
          left_lines = fetch_wrapped_lines(context, col_width, base_offset, displayable)
          render_column_lines(surface, bounds, left_lines, 1, col_width, context)
          draw_divider(surface, bounds, col_width)
          right_lines = fetch_wrapped_lines(context, col_width, base_offset + displayable,
                                            displayable)
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width, context)
        end

        ColumnContext = Struct.new(:col_width, :display_height, :left_offset, :right_offset, keyword_init: true)

        def render_absolute_columns(surface, bounds, context, col)
          cw = col.col_width
          dh = col.display_height
          left_lines = fetch_wrapped_lines(context, cw, col.left_offset, dh)
          render_column_lines(surface, bounds, left_lines, 1, cw, context)
          draw_divider(surface, bounds, cw)
          right_lines = fetch_wrapped_lines(context, cw, col.right_offset, dh)
          render_column_lines(surface, bounds, right_lines, cw + 5, cw, context)
        end

        def fetch_wrapped_lines(context, col_width, offset, length)
          st = context.state
          chapter_index = st.get(%i[reader current_chapter]) || 0
          super(context.document, chapter_index, col_width, offset, length)
        end
      end
    end
  end
end
