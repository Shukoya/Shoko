# frozen_string_literal: true

require_relative '../models/drawing_context'

module EbookReader
  module Concerns
    # Rendering helpers for the bookmarks screen
    module BookmarksUI
      include Constants::UIConstants

      def draw_bookmarks_screen(height, width)
        draw_bookmarks_header(width)

        if @bookmarks.empty?
          draw_empty_bookmarks(height, width)
        else
          draw_bookmarks_list(height, width)
        end

        draw_bookmarks_footer(height)
      end

      def draw_bookmarks_header(width)
        Terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}🔖 Bookmarks#{Terminal::ANSI::RESET}")
        Terminal.write(1, [width - 40, 40].max,
                       "#{Terminal::ANSI::DIM}[B/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")
      end

      def draw_empty_bookmarks(height, width)
        Terminal.write(height / 2, (width - MIN_COLUMN_WIDTH) / 2,
                       "#{Terminal::ANSI::DIM}No bookmarks yet.#{Terminal::ANSI::RESET}")
        Terminal.write((height / 2) + 1, (width - 30) / 2,
                       "#{Terminal::ANSI::DIM}Press 'b' while reading to add one.#{Terminal::ANSI::RESET}")
      end

      def draw_bookmarks_list(height, width)
        list_start = 4
        list_height = (height - 6) / 2
        visible_range = calculate_bookmark_visible_range(list_height)

        draw_bookmark_items(visible_range, list_start, width)
      end

      def calculate_bookmark_visible_range(list_height)
        visible_start = [@bookmark_selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, @bookmarks.length].min
        visible_start...visible_end
      end

      def draw_bookmark_items(range, list_start, width)
        range.each_with_index do |idx, row_idx|
          bookmark = @bookmarks[idx]
          chapter_title = @doc.get_chapter(bookmark.chapter_index)&.title ||
                          "Chapter #{bookmark.chapter_index + 1}"

          context = Models::BookmarkDrawingContext.new(
            bookmark: bookmark,
            chapter_title: chapter_title,
            index: idx,
            position: Models::Position.new(row: list_start + (row_idx * 2), col: 2),
            width: width
          )

          draw_bookmark_item(context)
        end
      end

      BookmarkItemContext = Struct.new(:position, :width, :line1, :line2, keyword_init: true)

      def draw_bookmark_item(context)
        bookmark = context.bookmark
        line1 = "Ch. #{bookmark.chapter_index + 1}: #{context.chapter_title}"
        line2 = "  > #{bookmark.text_snippet}"
        item_context = build_bookmark_item_context(context, line1, line2)
        if context.index == @bookmark_selected
          draw_selected_bookmark_item(item_context)
        else
          draw_unselected_bookmark_item(item_context)
        end
      end

      def build_bookmark_item_context(context, line1, line2)
        BookmarkItemContext.new(position: context.position, width: context.width,
                                line1: line1, line2: line2)
      end

      def draw_selected_bookmark_item(context)
        Terminal.write(context.position.row, 2,
                       "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
        Terminal.write(context.position.row, 4,
                       Terminal::ANSI::BRIGHT_WHITE + context.line1[0, context.width - 6] +
                       Terminal::ANSI::RESET)
        Terminal.write(context.position.row + 1, 4,
                       Terminal::ANSI::ITALIC + Terminal::ANSI::GRAY +
                       context.line2[0, context.width - 6] + Terminal::ANSI::RESET)
      end

      def draw_unselected_bookmark_item(context)
        Terminal.write(context.position.row, 4,
                       Terminal::ANSI::WHITE + context.line1[0, context.width - 6] +
                       Terminal::ANSI::RESET)
        Terminal.write(context.position.row + 1, 4,
                       Terminal::ANSI::DIM + Terminal::ANSI::GRAY +
                       context.line2[0, context.width - 6] + Terminal::ANSI::RESET)
      end

      def draw_bookmarks_footer(height)
        Terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • d Delete • B/ESC Back#{Terminal::ANSI::RESET}")
      end
    end
  end
end
