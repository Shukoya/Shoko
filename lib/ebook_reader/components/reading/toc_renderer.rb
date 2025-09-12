# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for table of contents display
      class TocRenderer < BaseViewRenderer
        ItemCtx = Struct.new(:chapter, :index, :selected_index, :y, keyword_init: true)
        def render_with_context(surface, bounds, context)
          st = context&.state
          doc = context&.document
          return unless st && doc
          selected_index = st.get(%i[reader toc_selected]) || 0

          render_header(surface, bounds)
          render_chapters_list(surface, bounds, doc.chapters, selected_index)
          render_footer(surface, bounds)
        end

        private

        def render_header(surface, bounds)
          w = bounds.width
          reset = Terminal::ANSI::RESET
          surface.write(bounds, 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT}📖 Table of Contents#{reset}")
          surface.write(bounds, 1, [w - 30, 40].max,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}[t/ESC] Back to Reading#{reset}")
        end

        def render_chapters_list(surface, bounds, chapters, selected_index)
          return if chapters.empty?

          list_start = 4
          list_height = bounds.height - 6

          visible_start = [selected_index - (list_height / 2), 0].max
          visible_end = [visible_start + list_height, chapters.length].min

          (visible_start...visible_end).each_with_index do |idx, row|
            chapter = chapters[idx]
            ctx = ItemCtx.new(chapter: chapter, index: idx, selected_index: selected_index, y: list_start + row)
            render_chapter_item(surface, bounds, ctx)
          end
        end

        def render_chapter_item(surface, bounds, ctx)
          w = bounds.width
          reset = Terminal::ANSI::RESET
          y = ctx.y
          idx = ctx.index
          selected = (idx == ctx.selected_index)
          line = (ctx.chapter.title || 'Untitled')[0, w - 6]

          if selected
            surface.write(bounds, y, 2,
                          "#{EbookReader::Constants::UIConstants::SELECTION_POINTER_COLOR}#{EbookReader::Constants::UIConstants::SELECTION_POINTER}#{reset}")
            surface.write(bounds, y, 4,
                          EbookReader::Constants::UIConstants::SELECTION_HIGHLIGHT + line + reset)
          else
            surface.write(bounds, y, 4,
                          EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + line + reset)
          end
        end

        def render_footer(surface, bounds)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, bounds.height - 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{reset}")
        end
      end
    end
  end
end
