# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for single-view reading mode (supports both dynamic and absolute page numbering)
      class SingleViewRenderer < BaseViewRenderer
        def initialize(page_numbering_mode = :absolute, dependencies = nil, controller = nil)
          super(dependencies, controller)
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

        def render_dynamic_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                 controller = nil, context = nil)
          lines.each_with_index do |line, idx|
            spacing = controller&.state ? EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(controller.state) : :normal
            row = start_row + (spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 2

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width,
                                       controller: controller, context: context)
          end
        end

        def render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, config,
                                  controller = nil, context = nil, displayable = nil)
          lines.each_with_index do |line, idx|
            spacing = controller&.state ? EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(controller.state) : :normal
            row = start_row + (spacing == :relaxed ? idx * 2 : idx)
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
                                                 EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))

          render_dynamic_lines(surface, bounds, page_data[:lines], start_row, col_start, col_width,
                               context.config, nil, context)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          displayable = adjust_for_line_spacing(content_height, EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))
          
          # Access wrap_lines through controller for now - in full refactor this would be a service
          wrapped = @controller.wrap_lines(chapter.lines || [], col_width) if @controller
          return unless wrapped
          
          return unless context&.state
          lines = wrapped.slice(context.state.get([:reader, :single_page]) || 0, displayable) || []
          start_row = calculate_centered_start_row(content_height, lines.size, EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))

          render_absolute_lines(surface, bounds, lines, start_row, col_start, col_width, context.config,
                                nil, context, displayable)
        end
      end
    end
  end
end
