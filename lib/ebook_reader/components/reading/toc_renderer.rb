# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for table of contents display
      class TocRenderer < BaseViewRenderer
        def render(surface, bounds, controller)
          doc = controller.doc
          state = controller.state
          selected_index = state.toc_selected || 0

          render_header(surface, bounds)
          render_chapters_list(surface, bounds, doc.chapters, selected_index)
          render_footer(surface, bounds)
        end

        private

        def render_header(surface, bounds)
          surface.write(bounds, 1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📖 Table of Contents#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [bounds.width - 30, 40].max,
                        "#{Terminal::ANSI::DIM}[t/ESC] Back to Reading#{Terminal::ANSI::RESET}")
        end

        def render_chapters_list(surface, bounds, chapters, selected_index)
          return if chapters.empty?

          list_start = 4
          list_height = bounds.height - 6

          visible_start = [selected_index - (list_height / 2), 0].max
          visible_end = [visible_start + list_height, chapters.length].min

          (visible_start...visible_end).each_with_index do |idx, row|
            chapter = chapters[idx]
            render_chapter_item(surface, bounds, chapter, idx, selected_index, list_start + row)
          end
        end

        def render_chapter_item(surface, bounds, chapter, idx, selected_index, y)
          line = (chapter.title || 'Untitled')[0, bounds.width - 6]

          if idx == selected_index
            surface.write(bounds, y, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
            surface.write(bounds, y, 4, Terminal::ANSI::BRIGHT_WHITE + line + Terminal::ANSI::RESET)
          else
            surface.write(bounds, y, 4, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
          end
        end

        def render_footer(surface, bounds)
          surface.write(bounds, bounds.height - 1, 2,
                        "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
