# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for bookmarks display
      class BookmarksRenderer < BaseViewRenderer
        BookmarkItemCtx = Struct.new(:row, :width, :bookmark, :chapter_title, :selected, keyword_init: true)
        def render_with_context(surface, bounds, context)
          st = context&.state
          return unless st

          bookmarks = st.get(%i[reader bookmarks]) || []
          doc = context.document

          render_header(surface, bounds)

          if bookmarks.empty?
            render_empty_message(surface, bounds)
          else
            render_bookmarks_list(surface, bounds, bookmarks, doc, st)
          end
        end

        private

        def render_header(surface, bounds)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT}🔖 Bookmarks#{reset}")
          surface.write(bounds, 1, [bounds.width - 40, 40].max,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}[B/ESC] Back [d] Delete#{reset}")
        end

        def render_empty_message(surface, bounds)
          reset = Terminal::ANSI::RESET
          message = 'No bookmarks yet. Press "b" while reading to add one.'
          surface.write(bounds, bounds.height / 2, (bounds.width - message.length) / 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}#{message}#{reset}")
        end

        def render_bookmarks_list(surface, bounds, bookmarks, doc, state)
          return unless state

          list_start = 4
          list_height = (bounds.height - 6) / 2
          selected = state.get(%i[reader bookmark_selected]) || 0

          visible_start = [selected - (list_height / 2), 0].max
          visible_end = [visible_start + list_height, bookmarks.length].min

          (visible_start...visible_end).each_with_index do |idx, row_idx|
            bookmark = bookmarks[idx]
            ch_idx = bookmark.chapter_index
            chapter = doc.get_chapter(ch_idx)
            chapter_title = chapter&.title || "Chapter #{ch_idx + 1}"

            row = list_start + (row_idx * 2)
            is_selected = (idx == selected)

            ctx = BookmarkItemCtx.new(row: row, width: bounds.width, bookmark: bookmark,
                                      chapter_title: chapter_title, selected: is_selected)
            render_bookmark_item(surface, bounds, ctx)
          end
        end

        def render_bookmark_item(surface, bounds, ctx)
          ui = EbookReader::Constants::UIConstants
          ansi = Terminal::ANSI
          row = ctx.row
          width = ctx.width
          bm = ctx.bookmark
          chapter_text = "Ch. #{bm.chapter_index + 1}: #{ctx.chapter_title[0, width - 20]}"
          text_snippet = bm.text_snippet[0, width - 8]

          if ctx.selected
            pointer = "#{ui::SELECTION_POINTER_COLOR}#{ui::SELECTION_POINTER}#{ansi::RESET}"
            title    = "#{ui::SELECTION_HIGHLIGHT}#{chapter_text}#{ansi::RESET}"
            snippet  = "#{ansi::ITALIC}#{ui::COLOR_TEXT_SECONDARY}#{text_snippet}#{ansi::RESET}"

            surface.write(bounds, row, 2, pointer)
          else
            title   = "#{ui::COLOR_TEXT_PRIMARY}#{chapter_text}#{ansi::RESET}"
            snippet = "#{ui::COLOR_TEXT_DIM}#{ui::COLOR_TEXT_SECONDARY}#{text_snippet}#{ansi::RESET}"

          end
          surface.write(bounds, row, 4, title)
          surface.write(bounds, row + 1, 6, snippet)
        end
      end
    end
  end
end
