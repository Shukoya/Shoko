# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      class SplitViewRenderer < BaseViewRenderer
        def render(surface, bounds, controller)
          chapter = controller.doc.get_chapter(controller.state.current_chapter)
          return unless chapter

          state = controller.state
          config = controller.config

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          display_height = adjust_for_line_spacing(content_height, config.line_spacing)
          wrapped = controller.wrap_lines(chapter.lines || [], col_width)

          # Ensure pages are properly initialized - delegate to controller
          if state.left_page.nil? || state.right_page.nil?
            controller.send(:initialize_split_pages_if_needed, display_height)
          end

          render_chapter_header(surface, bounds, state, chapter)
          render_left_column(surface, bounds, wrapped, state, config, col_width, display_height,
                             controller)
          render_divider(surface, bounds, col_width)
          render_right_column(surface, bounds, wrapped, state, config, col_width, display_height,
                              controller)
        end

        private


        def render_chapter_header(surface, bounds, state, chapter)
          chapter_info = "[#{state.current_chapter + 1}] #{chapter.title || 'Unknown'}"
          surface.write(bounds, 1, 1,
                        Terminal::ANSI::BLUE + chapter_info[0, bounds.width - 2].to_s + Terminal::ANSI::RESET)
        end

        def render_left_column(surface, bounds, wrapped, state, config, col_width, display_height,
                               controller)
          draw_column(surface, bounds,
                      lines: wrapped,
                      offset: state.left_page || 0,
                      col_width: col_width,
                      height: display_height,
                      row: 3, col: 1,
                      line_spacing: config.line_spacing,
                      controller: controller)
        end

        def render_right_column(surface, bounds, wrapped, state, config, col_width, display_height,
                                controller)
          draw_column(surface, bounds,
                      lines: wrapped,
                      offset: state.right_page || 0,
                      col_width: col_width,
                      height: display_height,
                      row: 3, col: col_width + 5,
                      line_spacing: config.line_spacing,
                      controller: controller)
        end

        def render_divider(surface, bounds, col_width)
          (3..[bounds.height - 1, 4].max).each do |row|
            surface.write(bounds, row, col_width + 3,
                          "#{Terminal::ANSI::GRAY}│#{Terminal::ANSI::RESET}")
          end
        end

        def draw_column(surface, bounds, lines:, offset:, col_width:, height:, row:, col:,
                        line_spacing:, controller:)
          display_lines = lines.slice(offset, height) || []
          display_lines.each_with_index do |line, idx|
            r = row + (line_spacing == :relaxed ? idx * 2 : idx)
            break if r >= bounds.height - 1

            draw_line(surface, bounds, line: line, row: r, col: col, width: col_width,
                                       controller: controller)
          end
        end
      end
    end
  end
end
