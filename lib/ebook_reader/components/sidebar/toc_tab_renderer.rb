# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        ItemCtx = Struct.new(:chapter, :index, :selected_index, :y, keyword_init: true)

        def initialize(state, dependencies = nil)
          super()
          @state = state
          @dependencies = dependencies
        end

        BoundsMetrics = Struct.new(:x, :y, :width, :height, keyword_init: true)

        def do_render(surface, bounds)
          metrics = metrics_for(bounds)
          doc = resolve_document
          state = @state

          chapters = doc.respond_to?(:chapters) ? doc.chapters : []
          entries_full = doc.respond_to?(:toc_entries) ? doc.toc_entries : []
          entries_full = fallback_entries(chapters) if entries_full.nil? || entries_full.empty?
          return render_empty_message(surface, bounds, metrics) if entries_full.empty?

          selected_chapter = state.get(%i[reader sidebar_toc_selected]) || 0

          # Handle filtering if active
          entries = get_filtered_entries(entries_full, state)
          selected_entry_index = find_entry_index(entries, selected_chapter)

          # Render filter input if active
          by = metrics.y
          content_start_y = by
          if state.get(%i[reader sidebar_toc_filter_active])
            render_filter_input(surface, bounds, metrics, state)
            content_start_y += 2
          end

          # Calculate visible area
          available_height = metrics.height - (content_start_y - by)
          render_entries_list(surface, bounds, metrics, entries, selected_entry_index, selected_chapter,
                              content_start_y, available_height)
        end

        private

        def metrics_for(bounds)
          BoundsMetrics.new(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
        end

        def resolve_document
          return @dependencies.resolve(:document) if @dependencies.respond_to?(:resolve)

          nil
        rescue StandardError
          nil
        end

        def render_empty_message(surface, bounds, metrics)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          by = metrics.y
          bw = metrics.width
          bh = metrics.height
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

        def get_filtered_entries(entries, state)
          filter = state.get(%i[reader sidebar_toc_filter])
          return entries if filter.nil? || filter.strip.empty?

          term = filter.downcase
          required = Set.new

          entries.each_with_index do |entry, idx|
            next unless entry.title.to_s.downcase.include?(term)

            required << idx
            current_level = entry.level
            parent_level = current_level - 1
            j = idx - 1
            while j >= 0 && parent_level >= 0
              prev = entries[j]
              if prev.level < current_level
                required << j
                current_level = prev.level
                parent_level = current_level - 1
              end
              j -= 1
            end
          end

          return [] if required.empty?

          entries.each_with_index.filter_map do |entry, idx|
            entry if required.include?(idx)
          end
        end

        def render_filter_input(surface, bounds, metrics, state)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          by = metrics.y
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

        def render_entries_list(surface, bounds, metrics, entries, selected_entry_index, selected_chapter_index,
                                start_y, height)
          return if entries.empty? || height <= 0

          window_start, window_items = UI::ListHelpers.slice_visible(entries, height, selected_entry_index)

          window_items.each_with_index do |entry, row|
            idx = window_start + row
            y_pos = start_y + row

            ctx = ItemCtx.new(chapter: entry,
                              index: idx,
                              selected_index: selected_chapter_index,
                              y: y_pos)
            render_chapter_item(surface, bounds, metrics, ctx)
          end
        end

        def render_chapter_item(surface, bounds, metrics, ctx)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          bw = metrics.width
          # Truncate title to fit width
          max_title_length = bw - 6
          y = ctx.y
          entry = ctx.chapter
          title = entry_title(entry)[0, max_title_length]
          indent = '  ' * [entry.level, 0].max
          navigable = entry.respond_to?(:chapter_index) ? !entry.chapter_index.nil? : true
          selected = navigable && entry.chapter_index == ctx.selected_index

          indicator = if selected
                        "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}"
                      elsif navigable
                        "#{COLOR_TEXT_DIM}○ #{reset}"
                      else
                        '  '
                      end

          base_color = if entry.level.zero?
                         COLOR_TEXT_ACCENT
                       elsif navigable
                         COLOR_TEXT_PRIMARY
                       else
                         COLOR_TEXT_DIM
                       end

          text = if selected
                   "#{SELECTION_HIGHLIGHT}#{indent}#{title}#{reset}"
                 else
                   "#{base_color}#{indent}#{title}#{reset}"
                 end

          surface.write(bounds, y, bx + 1, indicator)
          surface.write(bounds, y, bx + 3, text)
        end

        def find_entry_index(entries, chapter_index)
          entries.find_index { |entry| entry.chapter_index == chapter_index } || 0
        end

        def fallback_entries(chapters)
          chapters.each_with_index.map do |chapter, idx|
            Domain::Models::TOCEntry.new(title: chapter.title || "Chapter #{idx + 1}",
                                         href: nil,
                                         level: 1,
                                         chapter_index: idx,
                                         navigable: true)
          end
        end

        def entry_title(entry)
          title = entry.title || 'Untitled'
          entry.level.zero? ? title.upcase : title
        end
      end
    end
  end
end
