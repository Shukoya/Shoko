# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        def render(surface, bounds, controller)
          doc = controller.doc
          state = controller.state

          return render_empty_message(surface, bounds) if doc.chapters.empty?

          # Handle filtering if active
          chapters = get_filtered_chapters(doc.chapters, state)
          selected_index = state.sidebar_toc_selected || 0

          # Render filter input if active
          content_start_y = bounds.y
          if state.sidebar_toc_filter_active
            render_filter_input(surface, bounds, state)
            content_start_y += 2
          end

          # Calculate visible area
          available_height = bounds.height - (content_start_y - bounds.y)
          render_chapters_list(surface, bounds, chapters, selected_index, content_start_y,
                               available_height)
        end

        private

        def render_empty_message(surface, bounds)
          messages = [
            'No chapters found',
            '',
            "#{Terminal::ANSI::DIM}Content may still be loading#{Terminal::ANSI::RESET}",
          ]

          start_y = bounds.y + ((bounds.height - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bounds.x + [(bounds.width - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{Terminal::ANSI::DIM}#{message}#{Terminal::ANSI::RESET}")
          end
        end

        def get_filtered_chapters(chapters, state)
          filter = state.sidebar_toc_filter
          return chapters if filter.nil? || filter.strip.empty?

          chapters.select { |chapter| chapter.title&.downcase&.include?(filter.downcase) }
        end

        def render_filter_input(surface, bounds, state)
          filter_text = state.sidebar_toc_filter || ''
          cursor_visible = state.sidebar_toc_filter_active

          # Filter input line with modern styling
          prompt = "#{Terminal::ANSI::BRIGHT_CYAN}Search:#{Terminal::ANSI::RESET} "
          input_text = "#{Terminal::ANSI::WHITE}#{filter_text}#{Terminal::ANSI::RESET}"
          input_text += "#{Terminal::ANSI::REVERSE} #{Terminal::ANSI::RESET}" if cursor_visible

          input_line = "#{prompt}#{input_text}"
          surface.write(bounds, bounds.y, bounds.x + 1, input_line)

          # Help line with subtle styling
          help_text = "#{Terminal::ANSI::DIM}ESC to cancel#{Terminal::ANSI::RESET}"
          surface.write(bounds, bounds.y + 1, bounds.x + 1, help_text)
        end

        def render_chapters_list(surface, bounds, chapters, selected_index, start_y, height)
          return if chapters.empty? || height <= 0

          # Calculate scrolling
          visible_start = [selected_index - (height / 2), 0].max
          visible_end = [visible_start + height, chapters.length].min

          (visible_start...visible_end).each_with_index do |idx, row|
            chapter = chapters[idx]
            y_pos = start_y + row

            render_chapter_item(surface, bounds, chapter, idx, selected_index, y_pos)
          end
        end

        def render_chapter_item(surface, bounds, chapter, idx, selected_index, y)
          # Truncate title to fit width
          max_title_length = bounds.width - 6
          title = (chapter.title || "Chapter #{idx + 1}")[0, max_title_length]

          if idx == selected_index
            # Selected item with modern styling
            indicator = "#{Terminal::ANSI::BRIGHT_CYAN}●#{Terminal::ANSI::RESET}"
            surface.write(bounds, y, bounds.x + 1, indicator)
            surface.write(bounds, y, bounds.x + 3, "#{Terminal::ANSI::BRIGHT_WHITE}#{title}#{Terminal::ANSI::RESET}")
          else
            # Unselected item with subtle styling
            indicator = "#{Terminal::ANSI::DIM}○#{Terminal::ANSI::RESET}"
            surface.write(bounds, y, bounds.x + 1, indicator)
            surface.write(bounds, y, bounds.x + 3, "#{Terminal::ANSI::WHITE}#{title}#{Terminal::ANSI::RESET}")
          end
        end
      end
    end
  end
end
