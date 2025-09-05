# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        def initialize(dependencies)
          super(dependencies)
        end

        def render_with_context(surface, bounds, context)
          if context.page_numbering_mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        def render_divider(surface, bounds, col_width)
          (3..[bounds.height - 1, 4].max).each do |row|
            surface.write(bounds, row, col_width + 3,
                          "#{EbookReader::Constants::UIConstants::BORDER_PRIMARY}│#{Terminal::ANSI::RESET}")
          end
        end

        def render_column_lines(surface, bounds, lines, start_col, col_width, _config,
                                context = nil)
          draw_lines(surface, bounds, lines, 3, start_col, col_width, context)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_manager = context.page_calculator
          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config)
          displayable = adjust_for_line_spacing(content_height, spacing)

          chapter = context.current_chapter
          render_chapter_header_with_context(surface, bounds, context, chapter) if chapter

          if page_manager && (left_pd = page_manager.get_page(context.current_page_index))
            render_dynamic_left_column_with_context(surface, bounds, left_pd[:lines], col_width, context)
            render_divider(surface, bounds, col_width)
            if (right_pd = page_manager.get_page(context.current_page_index + 1))
              render_dynamic_right_column_with_context(surface, bounds, right_pd[:lines], col_width, context)
            end
            return
          end

          # Fallback when dynamic map not ready yet
          base_offset = (context.current_page_index || 0) * [displayable, 1].max
          left_lines = begin
            chapter_index = context.state.get(%i[reader current_chapter]) || 0
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width, base_offset, displayable)
            else
              (chapter&.lines || [])[base_offset, displayable] || []
            end
          end
          render_column_lines(surface, bounds, left_lines, 1, col_width, context.config, context)
          render_divider(surface, bounds, col_width)
          right_lines = begin
            chapter_index = context.state.get(%i[reader current_chapter]) || 0
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width,
                              base_offset + displayable, displayable)
            else
              (chapter&.lines || [])[base_offset + displayable, displayable] || []
            end
          end
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width, context.config, context)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          display_height = adjust_for_line_spacing(content_height, EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))

          return unless context&.state

          chapter_index = context.state.get(%i[reader current_chapter]) || 0
          left_offset  = context.state.get(%i[reader left_page]) || 0
          right_offset = context.state.get(%i[reader right_page]) || display_height

          # Render components
          render_chapter_header_with_context(surface, bounds, context, chapter)
          left_lines = begin
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width, left_offset, display_height)
            else
              (chapter&.lines || [])[left_offset, display_height] || []
            end
          end
          render_column_lines(surface, bounds, left_lines, 1, col_width, context.config, context)
          render_divider(surface, bounds, col_width)
          right_lines = begin
            chapter = context.document&.get_chapter(chapter_index)
            if @dependencies && @dependencies.registered?(:wrapping_service) && chapter
              ws = @dependencies.resolve(:wrapping_service)
              ws.wrap_window(chapter.lines || [], chapter_index, col_width, right_offset, display_height)
            else
              (chapter&.lines || [])[right_offset, display_height] || []
            end
          end
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width, context.config, context)
        end

        def render_chapter_header_with_context(surface, bounds, context, chapter)
          return unless context&.state

          chapter_info = "[#{context.state.get(%i[reader
                                                  current_chapter]) + 1}] #{chapter.title || 'Unknown'}"
          surface.write(bounds, 1, 1,
                        EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + chapter_info[0, bounds.width - 2].to_s + Terminal::ANSI::RESET)
        end

        def render_dynamic_left_column_with_context(surface, bounds, lines, col_width, context)
          render_column_lines(surface, bounds, lines, 1, col_width, context.config, context)
        end

        def render_dynamic_right_column_with_context(surface, bounds, lines, col_width, context)
          render_column_lines(surface, bounds, lines, col_width + 5, col_width, context.config,
                              context)
        end

        def render_left_column_with_context(surface, bounds, wrapped, context, col_width,
                                            display_height)
          return unless context&.state

          left_lines = wrapped.slice(context.state.get(%i[reader left_page]) || 0,
                                     display_height) || []
          render_column_lines(surface, bounds, left_lines, 1, col_width, context.config,
                              context)
        end

        def render_right_column_with_context(surface, bounds, wrapped, context, col_width,
                                             display_height)
          return unless context&.state

          right_lines = wrapped.slice(context.state.get(%i[reader right_page]) || 0,
                                      display_height) || []
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width,
                              context.config, context)
        end
      end
    end
  end
end
