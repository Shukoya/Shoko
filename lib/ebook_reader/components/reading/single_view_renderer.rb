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

        def render(surface, bounds, controller)
          if @page_numbering_mode == :dynamic
            render_dynamic_mode(surface, bounds, controller)
          else
            render_absolute_mode(surface, bounds, controller)
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
                                 controller)
          lines.each_with_index do |line, idx|
            row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 2

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width,
                                       controller: controller)
          end
        end

        def render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                  controller, displayable)
          lines.each_with_index do |line, idx|
            row = start_row + (config.line_spacing == :relaxed ? idx * 2 : idx)
            break if row >= (3 + displayable)

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width,
                                       controller: controller)
          end
        end

        def calculate_centered_start_row(content_height, lines_count, line_spacing)
          actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
          padding = (content_height - actual_lines)
          [3 + (padding / 2), 3].max
        end
      end
    end
  end
end
