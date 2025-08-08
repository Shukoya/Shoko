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
        renderer = reader.instance_variable_get(:@renderer)
        context = UI::ReaderRenderer::BookmarksContext.new(
          height: height,
          width: width,
          doc: reader.send(:doc),
          bookmarks: @bookmarks,
          selected: @selected
        )
        renderer.render_bookmarks_screen(context)
      end

      def handle_input(key)
        return handle_empty_input(key) if @bookmarks.empty?

        handler = input_handlers[key] || navigation_handler(key)
        handler&.call
      end

      def handle_empty_input(key)
        reader.switch_mode(:read) if escape_key?(key) || key == 'B'
      end

      # Rendering now delegated to UI::ReaderRenderer

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

      # Handles rendering of individual bookmark items in the bookmarks list.
      # This class encapsulates the display logic for both selected and
      # unselected bookmark states, providing consistent formatting.
      #
      # @example
      #   renderer = BookmarkRenderer.new(
      #     bookmark: bookmark,
      #     chapter: chapter,
      #     context: context,
      #     mode: mode
      #   )
      #   renderer.render
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

      # Footer/header/item rendering removed; kept navigation/selection logic only

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

      private

      def input_handlers
        @input_handlers ||= {
          "\e" => -> { reader.switch_mode(:read) },
          'B' => -> { reader.switch_mode(:read) },
          "\r" => -> { jump_to_bookmark },
          "\n" => -> { jump_to_bookmark },
          'd' => -> { delete_bookmark },
          'D' => -> { delete_bookmark },
        }
      end

      def navigation_handler(key)
        return unless navigation_key?(key)

        -> { @selected = handle_navigation_keys(key, @selected, @bookmarks.length - 1) }
      end
    end
  end
end
