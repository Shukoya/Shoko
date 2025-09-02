# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # Bookmarks tab renderer for sidebar
      class BookmarksTabRenderer < BaseComponent
        include Constants::UIConstants

        def initialize(controller)
          super()
          @controller = controller
        end

        def do_render(surface, bounds)
          bookmarks = @controller.state.get(%i[reader bookmarks]) || []
          doc = @controller.doc
          state = @controller.state
          selected_index = state.get(%i[reader sidebar_bookmarks_selected]) || 0

          return render_empty_message(surface, bounds) if bookmarks.empty?

          render_bookmarks_list(surface, bounds, bookmarks, doc, selected_index)
        end

        private

        def render_empty_message(surface, bounds)
          messages = [
            'No bookmarks yet',
            '',
            'Press "b" while reading',
            'to add a bookmark',
          ]

          start_y = bounds.y + ((bounds.height - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bounds.x + [(bounds.width - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}")
          end
        end

        def render_bookmarks_list(surface, bounds, bookmarks, doc, selected_index)
          # Each bookmark takes 2 lines: title/chapter + snippet
          item_height = 2
          visible_items = bounds.height / item_height

          # Calculate scrolling
          visible_start = [selected_index - (visible_items / 2), 0].max
          visible_end = [visible_start + visible_items, bookmarks.length].min

          current_y = bounds.y

          (visible_start...visible_end).each do |idx|
            bookmark = bookmarks[idx]
            break if current_y + item_height > bounds.y + bounds.height

            render_bookmark_item(surface, bounds, bookmark, doc, idx, selected_index, current_y)
            current_y += item_height
          end
        end

        def render_bookmark_item(surface, bounds, bookmark, doc, idx, selected_index, y)
          is_selected = (idx == selected_index)
          max_width = bounds.width - 4

          # Get chapter info
          chapter = doc.get_chapter(bookmark.chapter_index)
          chapter_title = chapter&.title || "Chapter #{bookmark.chapter_index + 1}"

          # First line: Chapter title with bookmark indicator
          prefix = is_selected ? "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{Terminal::ANSI::RESET}" : '  '
          chapter_text = chapter_title.to_s

          if chapter_text.length > max_width - 3
            chapter_text = "#{chapter_text[0, max_width - 6]}..."
          end

          # Modern bookmark icon
          bookmark_icon = "#{COLOR_TEXT_WARNING}◆#{Terminal::ANSI::RESET}"
          title_style = is_selected ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
          title_line = "#{prefix}#{bookmark_icon} #{title_style}#{chapter_text}#{Terminal::ANSI::RESET}"
          surface.write(bounds, y, bounds.x + 1, title_line)

          # Second line: Text snippet and position
          snippet = bookmark.text_snippet || ''
          snippet = "#{snippet[0, max_width - 11]}..." if snippet.length > max_width - 8

          # Add position indicator if available
          position_text = ''
          if bookmark.respond_to?(:position_percentage)
            position_text = " (#{bookmark.position_percentage}%)"
          end

          snippet_style = is_selected ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DIM
          snippet_line = "    #{snippet_style}\"#{snippet}\"#{position_text}#{Terminal::ANSI::RESET}"
          surface.write(bounds, y + 1, bounds.x + 1, snippet_line)
        end
      end
    end
  end
end
