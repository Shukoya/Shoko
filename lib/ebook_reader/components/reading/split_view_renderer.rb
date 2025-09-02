# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        def initialize(dependencies = nil, controller = nil)
          super
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
                                controller = nil, context = nil)
          lines.each_with_index do |line, idx|
            spacing = controller&.state ? EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(controller.state) : :normal
            row = 3 + (spacing == :relaxed ? idx * 2 : idx)
            break if row >= bounds.height - 1

            draw_line(surface, bounds, line: line, row: row, col: start_col, width: col_width,
                                       controller: controller, context: context)
          end
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          page_manager = context.page_manager
          return unless page_manager

          page_data = page_manager.get_page(context.current_page_index)
          return unless page_data

          # Get the next page for right column
          right_page_data = page_manager.get_page(context.current_page_index + 1)

          col_width, _content_height = layout_metrics(bounds.width, bounds.height, :split)

          # Render components
          chapter = context.current_chapter
          render_chapter_header_with_context(surface, bounds, context, chapter) if chapter
          render_dynamic_left_column_with_context(surface, bounds, page_data[:lines], col_width,
                                                  context)
          render_divider(surface, bounds, col_width)

          return unless right_page_data

          render_dynamic_right_column_with_context(surface, bounds, right_page_data[:lines],
                                                   col_width, context)
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          display_height = adjust_for_line_spacing(content_height, EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(context.config))

          # Access wrap_lines through controller for now - in full refactor this would be a service
          wrapped = @controller.wrap_lines(chapter.lines || [], col_width) if @controller
          return unless wrapped

          # Render components
          render_chapter_header_with_context(surface, bounds, context, chapter)
          render_left_column_with_context(surface, bounds, wrapped, context, col_width,
                                          display_height)
          render_divider(surface, bounds, col_width)
          render_right_column_with_context(surface, bounds, wrapped, context, col_width,
                                           display_height)
        end

        def render_chapter_header_with_context(surface, bounds, context, chapter)
          return unless context&.state

          chapter_info = "[#{context.state.get(%i[reader
                                                  current_chapter]) + 1}] #{chapter.title || 'Unknown'}"
          surface.write(bounds, 1, 1,
                        EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + chapter_info[0, bounds.width - 2].to_s + Terminal::ANSI::RESET)
        end

        def render_dynamic_left_column_with_context(surface, bounds, lines, col_width, context)
          render_column_lines(surface, bounds, lines, 1, col_width, context.config, nil, context)
        end

        def render_dynamic_right_column_with_context(surface, bounds, lines, col_width, context)
          render_column_lines(surface, bounds, lines, col_width + 5, col_width, context.config,
                              nil, context)
        end

        def render_left_column_with_context(surface, bounds, wrapped, context, col_width,
                                            display_height)
          return unless context&.state

          left_lines = wrapped.slice(context.state.get(%i[reader left_page]) || 0,
                                     display_height) || []
          render_column_lines(surface, bounds, left_lines, 1, col_width, context.config, nil,
                              context)
        end

        def render_right_column_with_context(surface, bounds, wrapped, context, col_width,
                                             display_height)
          return unless context&.state

          right_lines = wrapped.slice(context.state.get(%i[reader right_page]) || 0,
                                      display_height) || []
          render_column_lines(surface, bounds, right_lines, col_width + 5, col_width,
                              context.config, nil, context)
        end
      end
    end
  end
end
