# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for single-view reading mode (supports both dynamic and absolute page numbering)
      class SingleViewRenderer < BaseViewRenderer
        def initialize(page_numbering_mode = :absolute)
          super()
          @page_numbering_mode = page_numbering_mode
        end

        def view_render(surface, bounds, controller)
          if @page_numbering_mode == :dynamic
            render_dynamic_mode(surface, bounds, controller)
          else
            render_absolute_mode(surface, bounds, controller)
          end
        end

        def render_with_context(surface, bounds, context)
          if context.page_numbering_mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        def render_dynamic_mode(surface, bounds, controller)
          page_manager = controller.page_manager
          return unless page_manager

          page_data = page_manager.get_page(controller.state.current_page_index)
          return unless page_data

          config = controller.config
          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          start_row = calculate_center_start_row(content_height, page_data[:lines].size,
                                                 config.line_spacing)

          render_dynamic_lines(surface, bounds, page_data[:lines], start_row, col_start, col_width,
                               config, controller)
        end

        def render_absolute_mode(surface, bounds, controller)
          chapter = controller.doc.get_chapter(controller.state.current_chapter)
          return unless chapter

          config = controller.config
          state = controller.state

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          displayable = adjust_for_line_spacing(content_height, config.line_spacing)
          wrapped = controller.wrap_lines(chapter.lines || [], col_width)
          lines = wrapped.slice(state.single_page || 0, displayable) || []

          start_row = calculate_centered_start_row(content_height, lines.size, config.line_spacing)

          render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                controller, displayable)
        end

        def render_dynamic_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                 controller = nil, context = nil)
          lines.each_with_index do |line, idx|
            row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 2

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width,
                                       controller: controller, context: context)
          end
        end

        def render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                  controller = nil, context = nil, displayable = nil)
          lines.each_with_index do |line, idx|
            row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
            break if row >= (3 + (displayable || bounds.height))

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width,
                                       controller: controller, context: context)
          end
        end

        def calculate_centered_start_row(content_height, lines_count, line_spacing)
          actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
          padding = (content_height - actual_lines)
          [3 + (padding / 2), 3].max
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_manager = context.page_manager
          return unless page_manager

          page_data = page_manager.get_page(context.current_page_index)
          return unless page_data

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          start_row = calculate_center_start_row(content_height, page_data[:lines].size,
                                                 context.config.line_spacing)

          render_dynamic_lines(surface, bounds, page_data[:lines], start_row, col_start, col_width,
                               context.config, nil, context)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          displayable = adjust_for_line_spacing(content_height, context.config.line_spacing)
          
          # For absolute mode, we need access to wrap_lines method - fall back to legacy for now
          # This is a limitation of the current architecture
          # In a complete refactor, wrap_lines would be moved to a service
          
          # Since we can't access wrap_lines from context, we'll need to handle this differently
          # For now, we'll delegate back to the legacy method
          raise NotImplementedError, 'Absolute mode with context not yet fully implemented - use legacy view_render'
        end
      end
    end
  end
end
