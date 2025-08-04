# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # Bookmark management interface
    class BookmarksMode < BaseMode
      include Concerns::InputHandler

      def initialize(reader)
        super
        @selected = 0
        @bookmarks = reader.send(:bookmarks)
      end

      def draw(height, width)
        draw_header(width)

        if @bookmarks.empty?
          draw_empty_state(height, width)
        else
          draw_bookmark_list(height, width)
        end

        draw_footer(height)
      end

      def handle_input(key)
        return handle_empty_input(key) if @bookmarks.empty?

        if escape_key?(key) || key == 'B'
          reader.switch_mode(:read)
        elsif navigation_key?(key)
          @selected = handle_navigation_keys(key, @selected, @bookmarks.length - 1)
        elsif enter_key?(key)
          jump_to_bookmark
        elsif %w[d D].include?(key)
          delete_bookmark
        end
      end

      def handle_empty_input(key)
        reader.switch_mode(:read) if escape_key?(key) || key == 'B'
      end

      def draw_header(width)
        terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}🔖 Bookmarks#{Terminal::ANSI::RESET}")
        terminal.write(1, [width - 40, 40].max,
                       "#{Terminal::ANSI::DIM}[B/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")
      end

      def draw_empty_state(height, width)
        terminal.write(height / 2, (width - 20) / 2,
                       "#{Terminal::ANSI::DIM}No bookmarks yet#{Terminal::ANSI::RESET}")
      end

      def draw_bookmark_list(height, width)
        list_start = 4
        items_per_page = (height - 6) / 2

        visible_range = calculate_visible_range(items_per_page)

        visible_range.each_with_index do |idx, row_idx|
          bookmark = @bookmarks[idx]
          context = BookmarkItemContext.new(bookmark, idx, list_start + (row_idx * 2), width,
                                            idx == @selected)
          draw_bookmark_item(context)
        end
      end

      BookmarkItemContext = Struct.new(:bookmark, :index, :row, :width, :selected)
      BookmarkDrawContext = Struct.new(:row, :width, :bookmark, :chapter_title)

      def draw_bookmark_item(context)
        doc = reader.send(:doc)
        chapter = doc.get_chapter(context.bookmark.chapter_index)

        bookmark_renderer = BookmarkRenderer.new(
          bookmark: context.bookmark,
          chapter: chapter,
          context: context,
          mode: self
        )

        bookmark_renderer.render
      end

      class BookmarkRenderer
        def initialize(bookmark:, chapter:, context:, mode:)
          @bookmark = bookmark
          @chapter = chapter
          @context = context
          @mode = mode
        end

        def render
          if @context.selected
            render_selected
          else
            render_unselected
          end
        end

        private

        def render_selected
          draw_context = build_draw_context
          @mode.send(:draw_selected_bookmark, draw_context)
        end

        def render_unselected
          draw_context = build_draw_context
          @mode.send(:draw_unselected_bookmark, draw_context)
        end

        def build_draw_context
          BookmarkDrawContext.new(
            row: @context.row,
            width: @context.width,
            bookmark: @bookmark,
            chapter_title: chapter_title
          )
        end

        def chapter_title
          @chapter&.title || "Chapter #{@bookmark.chapter_index + 1}"
        end
      end

      def draw_selected_bookmark(context)
        terminal.write(context.row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")

        chapter_text = "Ch. #{context.bookmark.chapter_index + 1}: " \
                       "#{context.chapter_title[0, context.width - 20]}"
        terminal.write(context.row, 4,
                       "#{Terminal::ANSI::BRIGHT_WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")

        bookmark_text = context.bookmark.text_snippet[0, context.width - 8]
        terminal.write(context.row + 1, 6,
                       "#{Terminal::ANSI::ITALIC}#{Terminal::ANSI::GRAY}#{bookmark_text}#{Terminal::ANSI::RESET}")
      end

      def draw_unselected_bookmark(context)
        chapter_text = "Ch. #{context.bookmark.chapter_index + 1}: " \
                       "#{context.chapter_title[0, context.width - 20]}"
        terminal.write(context.row, 4,
                       "#{Terminal::ANSI::WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")

        bookmark_text = context.bookmark.text_snippet[0, context.width - 8]
        terminal.write(context.row + 1, 6,
                       "#{Terminal::ANSI::DIM}#{Terminal::ANSI::GRAY}#{bookmark_text}#{Terminal::ANSI::RESET}")
      end

      def draw_footer(height)
        terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • d Delete • B/ESC Back#{Terminal::ANSI::RESET}")
      end

      def calculate_visible_range(items_per_page)
        visible_start = [@selected - (items_per_page / 2), 0].max
        visible_end = [visible_start + items_per_page, @bookmarks.length].min
        visible_start...visible_end
      end

      def jump_to_bookmark
        bookmark = @bookmarks[@selected]
        return unless bookmark

        reader.send(:jump_to_bookmark)
      end

      def delete_bookmark
        bookmark = @bookmarks[@selected]
        return unless bookmark

        reader.send(:delete_selected_bookmark)
        @bookmarks = reader.send(:bookmarks)
        @selected = [@selected, @bookmarks.length - 1].min if @bookmarks.any?
      end
    end
  end
end
