# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        ItemCtx = Struct.new(:chapter, :index, :selected_index, :y, keyword_init: true)

        def initialize(controller)
          super()
          @controller = controller
        end

        def do_render(surface, bounds)
          doc = @controller.doc
          state = @controller.state

          chapters_full = doc.chapters
          return render_empty_message(surface, bounds) if chapters_full.empty?

          # Handle filtering if active
          chapters = get_filtered_chapters(chapters_full, state)
          selected_index = state.get(%i[reader sidebar_toc_selected]) || 0

          # Render filter input if active
          by = bounds.y
          content_start_y = by
          if state.get(%i[reader sidebar_toc_filter_active])
            render_filter_input(surface, bounds, state)
            content_start_y += 2
          end

          # Calculate visible area
          available_height = bounds.height - (content_start_y - by)
          render_chapters_list(surface, bounds, chapters, selected_index, content_start_y,
                               available_height)
        end

        private

        def render_empty_message(surface, bounds)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          by = bounds.y
          bw = bounds.width
          bh = bounds.height
          messages = [
            'No chapters found',
            '',
            "#{COLOR_TEXT_DIM}Content may still be loading#{reset}",
          ]

          start_y = by + ((bh - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bx + [(bw - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{reset}")
          end
        end

        def get_filtered_chapters(chapters, state)
          filter = state.get(%i[reader sidebar_toc_filter])
          return chapters if filter.nil? || filter.strip.empty?

          chapters.select { |chapter| chapter.title&.downcase&.include?(filter.downcase) }
        end

        def render_filter_input(surface, bounds, state)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          by = bounds.y
          filter_text = state.get(%i[reader sidebar_toc_filter]) || ''
          cursor_visible = state.get(%i[reader sidebar_toc_filter_active])

          # Filter input line with modern styling
          prompt = "#{COLOR_TEXT_ACCENT}Search:#{reset} "
          input_text = "#{COLOR_TEXT_PRIMARY}#{filter_text}#{reset}"
          input_text += "#{Terminal::ANSI::REVERSE} #{reset}" if cursor_visible

          input_line = "#{prompt}#{input_text}"
          x1 = bx + 1
          surface.write(bounds, by, x1, input_line)

          # Help line with subtle styling
          help_text = "#{COLOR_TEXT_DIM}ESC to cancel#{reset}"
          surface.write(bounds, by + 1, x1, help_text)
        end

        def render_chapters_list(surface, bounds, chapters, selected_index, start_y, height)
          return if chapters.empty? || height <= 0

          # Calculate scrolling
          visible_start = [selected_index - (height / 2), 0].max
          visible_end = [visible_start + height, chapters.length].min

          (visible_start...visible_end).each_with_index do |idx, row|
            chapter = chapters[idx]
            y_pos = start_y + row

            ctx = ItemCtx.new(chapter: chapter, index: idx, selected_index: selected_index, y: y_pos)
            render_chapter_item(surface, bounds, ctx)
          end
        end

        def render_chapter_item(surface, bounds, ctx)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          bw = bounds.width
          # Truncate title to fit width
          max_title_length = bw - 6
          idx = ctx.index
          y = ctx.y
          title = (ctx.chapter.title || "Chapter #{idx + 1}")[0, max_title_length]

          indicator = if idx == ctx.selected_index
                        # Selected item with modern styling
                        "#{COLOR_TEXT_ACCENT}●#{reset}"
                      else
                        # Unselected item with subtle styling
                        "#{COLOR_TEXT_DIM}○#{reset}"
                      end
          surface.write(bounds, y, bx + 1, indicator)
          surface.write(bounds, y, bx + 3, "#{COLOR_TEXT_PRIMARY}#{title}#{reset}")
        end
      end
    end
  end
end
