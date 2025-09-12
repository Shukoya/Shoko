# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # Bookmarks tab renderer for sidebar
      class BookmarksTabRenderer < BaseComponent
        include Constants::UIConstants

        ItemCtx = Struct.new(:bookmark, :doc, :index, :selected_index, :y, keyword_init: true)

        def initialize(controller)
          super()
          @controller = controller
        end

        def do_render(surface, bounds)
          state = @controller.state
          bookmarks = state.get(%i[reader bookmarks]) || []
          doc = @controller.doc
          selected_index = state.get(%i[reader sidebar_bookmarks_selected]) || 0

          return render_empty_message(surface, bounds) if bookmarks.empty?

          render_bookmarks_list(surface, bounds, bookmarks, doc, selected_index)
        end

        private

      def render_empty_message(surface, bounds)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          by = bounds.y
          bw = bounds.width
          bh = bounds.height
          messages = [
            'No bookmarks yet',
            '',
            'Press "b" while reading',
            'to add a bookmark',
          ]

          start_y = by + ((bh - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bx + [(bw - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{reset}")
          end
      end

        def render_bookmarks_list(surface, bounds, bookmarks, doc, selected_index)
          # Each bookmark takes 2 lines: title/chapter + snippet
          item_height = 2
          bh = bounds.height
          by = bounds.y
          visible_items = bh / item_height

          # Calculate scrolling
          visible_start = [selected_index - (visible_items / 2), 0].max
          visible_end = [visible_start + visible_items, bookmarks.length].min

          current_y = by
          end_y = by + bh

          (visible_start...visible_end).each do |idx|
            bookmark = bookmarks[idx]
            break if current_y + item_height > end_y

            ctx = ItemCtx.new(bookmark: bookmark, doc: doc, index: idx, selected_index: selected_index, y: current_y)
            render_bookmark_item(surface, bounds, ctx)
            current_y += item_height
          end
        end

        def render_bookmark_item(surface, bounds, ctx)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          bw = bounds.width
          row = ctx.y
          col = bx + 1
          bm = ctx.bookmark
          is_selected = (ctx.index == ctx.selected_index)
          max_width = bw - 4

          # Get chapter info
          ch_index = bm.chapter_index
          chapter = ctx.doc.get_chapter(ch_index)
          chapter_title = chapter&.title || "Chapter #{ch_index + 1}"

          # First line: Chapter title with bookmark indicator
          if is_selected
            prefix = "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}"
            title_style = SELECTION_HIGHLIGHT
            snippet_style = COLOR_TEXT_SECONDARY
          else
            prefix = '  '
            title_style = COLOR_TEXT_PRIMARY
            snippet_style = COLOR_TEXT_DIM
          end
          chapter_text = chapter_title.to_s
          chapter_text = "#{chapter_text[0, max_width - 6]}..." if chapter_text.length > max_width - 3

          # Modern bookmark icon
          bookmark_icon = "#{COLOR_TEXT_WARNING}◆#{reset}"
          title_line = "#{prefix}#{bookmark_icon} #{title_style}#{chapter_text}#{reset}"
          surface.write(bounds, row, col, title_line)

          # Second line: Text snippet and position
          snippet = bm.text_snippet || ''
          snippet = "#{snippet[0, max_width - 11]}..." if snippet.length > max_width - 8

          # Add position indicator if available
          position_text = ''
          position_text = " (#{bm.position_percentage}%)" if bm.respond_to?(:position_percentage)

          snippet_line = "    #{snippet_style}\"#{snippet}\"#{position_text}#{reset}"
          surface.write(bounds, row + 1, col, snippet_line)
        end
      end
    end
  end
end
