# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        def render(surface, bounds, controller)
          if controller.config.page_numbering_mode == :dynamic
            render_dynamic_mode(surface, bounds, controller)
          else
            render_absolute_mode(surface, bounds, controller)
          end
        end

        private

        # Dynamic mode: Uses PageManager for pre-calculated page content
        def render_dynamic_mode(surface, bounds, controller)
          page_manager = controller.page_manager
          return unless page_manager

          page_data = page_manager.get_page(controller.state.current_page_index)
          return unless page_data

          state = controller.state
          config = controller.config
          
          # Get the next page for right column
          right_page_data = page_manager.get_page(controller.state.current_page_index + 1)

          col_width, _content_height = layout_metrics(bounds.width, bounds.height, :split)
          
          # Render components
          chapter = controller.doc.get_chapter(state.current_chapter)
          render_chapter_header(surface, bounds, state, chapter) if chapter
          render_dynamic_left_column(surface, bounds, page_data[:lines], col_width, config, controller)
          render_divider(surface, bounds, col_width)
          
          if right_page_data
            render_dynamic_right_column(surface, bounds, right_page_data[:lines], col_width, config, controller)
          end
        end

        # Absolute mode: Manually wraps and slices chapter content
        def render_absolute_mode(surface, bounds, controller)
          chapter = controller.doc.get_chapter(controller.state.current_chapter)
          return unless chapter

          state = controller.state
          config = controller.config

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          display_height = adjust_for_line_spacing(content_height, config.line_spacing)
          wrapped = controller.wrap_lines(chapter.lines || [], col_width)

          # Render components
          render_chapter_header(surface, bounds, state, chapter)
          render_left_column(surface, bounds, wrapped, state, config, col_width, display_height, controller)
          render_divider(surface, bounds, col_width)
          render_right_column(surface, bounds, wrapped, state, config, col_width, display_height, controller)
        end

        def render_chapter_header(surface, bounds, state, chapter)
          chapter_info = "[#{state.current_chapter + 1}] #{chapter.title || 'Unknown'}"
          surface.write(bounds, 1, 1,
                        Terminal::ANSI::BLUE + chapter_info[0, bounds.width - 2].to_s + Terminal::ANSI::RESET)
        end

        def render_left_column(surface, bounds, wrapped, state, config, col_width, display_height,
                               controller)
          left_lines = wrapped.slice(state.left_page || 0, display_height) || []
          render_column_lines(surface, bounds, left_lines, 1, col_width, config, controller)
        end

        def render_right_column(surface, bounds, wrapped, state, config, col_width, display_height,
                                controller)
          right_lines = wrapped.slice(state.right_page || 0, display_height) || []
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width, config, controller)
        end

        def render_divider(surface, bounds, col_width)
          (3..[bounds.height - 1, 4].max).each do |row|
            surface.write(bounds, row, col_width + 3,
                          "#{Terminal::ANSI::GRAY}│#{Terminal::ANSI::RESET}")
          end
        end

        def render_dynamic_left_column(surface, bounds, lines, col_width, config, controller)
          render_column_lines(surface, bounds, lines, 1, col_width, config, controller)
        end

        def render_dynamic_right_column(surface, bounds, lines, col_width, config, controller)
          render_column_lines(surface, bounds, lines, col_width + 5, col_width, config, controller)
        end

        def render_column_lines(surface, bounds, lines, start_col, col_width, config, controller)
          lines.each_with_index do |line, idx|
            row = 3 + (config.line_spacing == :relaxed ? idx * 2 : idx)
            break if row >= bounds.height - 1

            draw_line(surface, bounds, line: line, row: row, col: start_col, width: col_width,
                                       controller: controller)
          end
        end

      end
    end
  end
end
