# frozen_string_literal: true

require_relative 'base_view_renderer'

module EbookReader
  module Components
    module Reading
      # Renderer for bookmarks display
      class BookmarksRenderer < BaseViewRenderer
        def initialize(dependencies = nil, controller = nil)
          super
        end

        def render_with_context(surface, bounds, context)
          return unless context&.state

          bookmarks = context.state.get(%i[reader bookmarks]) || []
          doc = context.document

          render_header(surface, bounds)

          if bookmarks.empty?
            render_empty_message(surface, bounds)
          else
            render_bookmarks_list(surface, bounds, bookmarks, doc, context.state)
          end
        end

        private

        def render_header(surface, bounds)
          surface.write(bounds, 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT}🔖 Bookmarks#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [bounds.width - 40, 40].max,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}[B/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")
        end

        def render_empty_message(surface, bounds)
          message = 'No bookmarks yet. Press "b" while reading to add one.'
          surface.write(bounds, bounds.height / 2, (bounds.width - message.length) / 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}")
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
            chapter = doc.get_chapter(bookmark.chapter_index)
            chapter_title = chapter&.title || "Chapter #{bookmark.chapter_index + 1}"

            row = list_start + (row_idx * 2)
            is_selected = (idx == selected)

            render_bookmark_item(surface, bounds, row, bounds.width, bookmark, chapter_title,
                                 is_selected)
          end
        end

        def render_bookmark_item(surface, bounds, row, width, bookmark, chapter_title, selected)
          chapter_text = "Ch. #{bookmark.chapter_index + 1}: #{chapter_title[0, width - 20]}"
          text_snippet = bookmark.text_snippet[0, width - 8]

          if selected
            surface.write(bounds, row, 2,
                          "#{EbookReader::Constants::UIConstants::SELECTION_POINTER_COLOR}#{EbookReader::Constants::UIConstants::SELECTION_POINTER}#{Terminal::ANSI::RESET}")
            surface.write(bounds, row, 4,
                          "#{EbookReader::Constants::UIConstants::SELECTION_HIGHLIGHT}#{chapter_text}#{Terminal::ANSI::RESET}")
            surface.write(bounds, row + 1, 6,
                          "#{Terminal::ANSI::ITALIC}#{EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY}#{text_snippet}#{Terminal::ANSI::RESET}")
          else
            surface.write(bounds, row, 4,
                          "#{EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY}#{chapter_text}#{Terminal::ANSI::RESET}")
            surface.write(bounds, row + 1, 6,
                          "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}#{EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY}#{text_snippet}#{Terminal::ANSI::RESET}")
          end
        end
      end
    end
  end
end
