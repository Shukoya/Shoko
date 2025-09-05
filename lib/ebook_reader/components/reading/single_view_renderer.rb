# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for single-view reading mode (supports both dynamic and absolute page numbering)
      class SingleViewRenderer < BaseViewRenderer
        def initialize(page_numbering_mode = :absolute, dependencies)
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

        def render_dynamic_lines(surface, bounds, lines, start_row, col_start, col_width, _config,
                                 context = nil)
          draw_lines(surface, bounds, lines, start_row, col_start, col_width, context)
        end

        def render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, _config,
                                  context = nil, _displayable = nil)
          draw_lines(surface, bounds, lines, start_row, col_start, col_width, context)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_manager = context.page_calculator
          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config)
          displayable = adjust_for_line_spacing(content_height, spacing)

          if page_manager && (pd = page_manager.get_page(context.current_page_index))
            start_row = calculate_center_start_row(content_height, pd[:lines].size, spacing)
            render_dynamic_lines(surface, bounds, pd[:lines], start_row, col_start, col_width,
                                 context.config, context)
            return
          end

          # Fallback when dynamic map not ready yet: use pending precise line_offset if available
          pending = context.state.get(%i[reader pending_progress]) if context&.state
          line_offset = pending && (pending[:line_offset] || pending['line_offset'])
          offset = if line_offset
                     line_offset.to_i
                   else
                     (context.current_page_index || 0) * [displayable, 1].max
                   end
          lines = begin
            chapter_index = context.state.get(%i[reader current_chapter]) || 0
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width, offset, displayable)
            else
              (chapter&.lines || [])[offset, displayable] || []
            end
          end
          start_row = calculate_center_start_row(content_height, lines.size, spacing)
          render_dynamic_lines(surface, bounds, lines, start_row, col_start, col_width,
                               context.config, context)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          displayable = adjust_for_line_spacing(content_height, EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))

          return unless context&.state

          offset = context.state.get(%i[reader single_page]) || 0
          chapter_index = context.state.get(%i[reader current_chapter]) || 0
          lines = begin
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width, offset, displayable)
            else
              (chapter&.lines || [])[offset, displayable] || []
            end
          end
          spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config)
          start_row = calculate_center_start_row(content_height, lines.size, spacing)

          render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, context.config,
                                context, displayable)
        end
      end
    end
  end
end
