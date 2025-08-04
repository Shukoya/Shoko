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

      BookmarkParams = Struct.new(:idx, :row_idx, :list_start, :width, keyword_init: true)

      def draw_bookmark_items(range, list_start, width)
        range.each_with_index do |idx, row_idx|
          params = BookmarkParams.new(idx: idx, row_idx: row_idx,
                                      list_start: list_start,
                                      width: width)
          context = build_bookmark_context(params)
          draw_bookmark_item(context)
        end
      end

      def build_bookmark_context(params)
        bookmark = @bookmarks[params.idx]
        chapter_title = extract_chapter_title(bookmark)
        position = calculate_bookmark_position(params)

        Models::BookmarkDrawingContext.new(
          bookmark: bookmark,
          chapter_title: chapter_title,
          index: params.idx,
          position: position,
          width: params.width
        )
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
        draw_bookmark_pointer(context.position.row)
        draw_bookmark_text(context, Terminal::ANSI::BRIGHT_WHITE,
                           Terminal::ANSI::ITALIC + Terminal::ANSI::GRAY)
      end

      def draw_unselected_bookmark_item(context)
        draw_bookmark_text(context, Terminal::ANSI::WHITE,
                           Terminal::ANSI::DIM + Terminal::ANSI::GRAY)
      end

      def draw_bookmark_pointer(row)
        Terminal.write(row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
      end

      def draw_bookmark_text(context, style1, style2)
        line1 = formatted_line(context.line1, context.width - 6, style1)
        line2 = formatted_line(context.line2, context.width - 6, style2)

        Terminal.write(context.position.row, 4, line1)
        Terminal.write(context.position.row + 1, 4, line2)
      end

      def formatted_line(text, width, style)
        style + text[0, width] + Terminal::ANSI::RESET
      end

      def draw_bookmarks_footer(height)
        Terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • d Delete • B/ESC Back#{Terminal::ANSI::RESET}")
      end

      private

      def extract_chapter_title(bookmark)
        @doc.get_chapter(bookmark.chapter_index)&.title ||
          "Chapter #{bookmark.chapter_index + 1}"
      end

      def calculate_bookmark_position(params)
        Models::Position.new(
          row: params.list_start + (params.row_idx * 2),
          col: 2
        )
      end
    end
  end
end
