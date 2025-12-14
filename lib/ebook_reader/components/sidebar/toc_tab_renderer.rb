# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        ItemCtx = Struct.new(:entries, :entry, :index, :selected_index, :y, keyword_init: true)

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

          selected_full_index = (state.get(%i[reader sidebar_toc_selected]) || 0).to_i
          selected_full_index = selected_full_index.clamp(0, [entries_full.length - 1, 0].max)

          # Handle filtering if active
          entries = get_filtered_entries(entries_full, state)
          selected_entry = entries_full[selected_full_index]
          selected_entry_index = selected_entry ? entries.index(selected_entry) : 0
          selected_entry_index ||= 0

          by = metrics.y
          content_start_y = render_header(surface, bounds, metrics, doc, entries_full.length)

          # Render filter input if active
          if state.get(%i[reader sidebar_toc_filter_active])
            content_start_y = render_filter_input(surface, bounds, metrics, state, content_start_y)
          end

          footer_height = 2
          available_height = metrics.height - (content_start_y - by) - footer_height
          available_height = [available_height, 0].max

          render_entries_list(surface, bounds, metrics, entries, selected_entry_index,
                              content_start_y, available_height)

          render_footer(surface, bounds, metrics)
        end

        private

        def metrics_for(bounds)
          BoundsMetrics.new(x: 1, y: 1, width: bounds.width, height: bounds.height)
        end

        def resolve_document
          return @dependencies.resolve(:document) if @dependencies.respond_to?(:resolve)

          nil
        rescue StandardError
          nil
        end

        def render_empty_message(surface, bounds, metrics)
          reset = Terminal::ANSI::RESET
          bw = metrics.width
          bh = metrics.height
          messages = [
            'No chapters found',
            '',
            'Content may still be loading',
          ]

          start_y = ((bh - messages.length) / 2) + 1
          messages.each_with_index do |message, i|
            msg_width = EbookReader::Helpers::TextMetrics.visible_length(message)
            x = [(bw - msg_width) / 2, 2].max
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

        def render_header(surface, bounds, metrics, doc, total_entries)
          reset = Terminal::ANSI::RESET
          title_plain = doc_title(doc)
          title_width = EbookReader::Helpers::TextMetrics.visible_length(title_plain)
          title = "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{title_plain}#{reset}"

          subtitle_plain = "#{total_entries} entries"
          subtitle_width = EbookReader::Helpers::TextMetrics.visible_length(subtitle_plain)
          subtitle = "#{COLOR_TEXT_DIM}#{subtitle_plain}#{reset}"

          bx = metrics.x
          by = metrics.y
          bw = metrics.width

          divider = "#{COLOR_TEXT_DIM}#{'─' * [bw - 2, 0].max}#{reset}"
          surface.write(bounds, by, bx + 1, title)
          if bw > subtitle_width + 2
            min_subtitle_col = bx + 1 + title_width + 2
            right_subtitle_col = bx + bw - subtitle_width - 1
            subtitle_col = [right_subtitle_col, min_subtitle_col].max
            surface.write(bounds, by, subtitle_col, subtitle)
          end
          surface.write(bounds, by + 1, bx + 1, divider)
          by + 2
        end

        def doc_title(doc)
          return 'CONTENTS' unless doc

          metadata_title = doc.respond_to?(:metadata) ? doc.metadata&.fetch(:title, nil) : nil
          title = metadata_title || (doc.respond_to?(:title) ? doc.title : nil)
          return 'CONTENTS' unless title && !title.to_s.strip.empty?

          title.to_s.strip.upcase
        end

        def render_filter_input(surface, bounds, metrics, state, start_y)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          by = start_y
          filter_text = state.get(%i[reader sidebar_toc_filter]) || ''
          cursor_visible = state.get(%i[reader sidebar_toc_filter_active])

          # Filter input line with modern styling
          prompt = "#{COLOR_TEXT_ACCENT}SEARCH ▸#{reset} "
          input_text = "#{COLOR_TEXT_PRIMARY}#{filter_text}#{reset}"
          input_text += "#{Terminal::ANSI::REVERSE} #{reset}" if cursor_visible

          input_line = "#{prompt}#{input_text}"
          x1 = bx + 1
          surface.write(bounds, by, x1, input_line)

          # Help line with subtle styling
          help_text = "#{COLOR_TEXT_DIM}ESC cancel#{reset}"
          surface.write(bounds, by + 1, x1, help_text)
          by + 2
        end

        def render_entries_list(surface, bounds, metrics, entries, selected_entry_index,
                                start_y, height)
          return if entries.empty? || height <= 0

          window_start, window_items = UI::ListHelpers.slice_visible(entries, height, selected_entry_index)

          window_items.each_with_index do |entry, row|
            idx = window_start + row
            y_pos = start_y + row

            ctx = ItemCtx.new(entries: entries,
                              entry: entry,
                              index: idx,
                              selected_index: selected_entry_index,
                              y: y_pos)
            render_chapter_item(surface, bounds, metrics, ctx)
          end
        end

        def render_chapter_item(surface, bounds, metrics, ctx)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          bw = metrics.width
          y = ctx.y
          entry = ctx.entry
          entries = ctx.entries
          max_width = [bw - 2, 0].max
          selected = ctx.index == ctx.selected_index

          gutter = selected ? "#{COLOR_TEXT_ACCENT}▎#{reset}" : "#{COLOR_TEXT_DIM}│#{reset}"
          surface.write(bounds, y, bx, gutter)

          prefix_plain = branch_prefix(entries, ctx.index)
          icon_plain = entry_icon(entries, ctx.index, entry)
          icon_color = icon_color_for(entry)
          prefix_w = EbookReader::Helpers::TextMetrics.visible_length(prefix_plain)
          icon_w = EbookReader::Helpers::TextMetrics.visible_length(icon_plain)
          available_title_width = [max_width - prefix_w - icon_w - 1, 0].max
          title_plain = UI::TextUtils.truncate_text(entry_title(entry), available_title_width)

          segments = build_segments(prefix_plain, icon_plain, icon_color, title_plain, entry)
          line = compose_line(segments, selected)
          surface.write(bounds, y, bx + 2, line)
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

        def navigable?(entry)
          entry.respond_to?(:chapter_index) ? !entry.chapter_index.nil? : true
        end

        def build_segments(prefix, icon, icon_color, title, entry)
          segments = []
          segments << [prefix, COLOR_TEXT_DIM] unless prefix.empty?
          segments << [icon, icon_color]
          segments << [' ', nil]
          segments << [title, title_color_for(entry)]
          segments
        end

        def compose_line(segments, selected)
          reset = Terminal::ANSI::RESET
          if selected
            line = "#{Terminal::ANSI::BG_GREY}#{Terminal::ANSI::WHITE}"
            segments.each { |text, _color| line << text }
            line << reset
            line
          else
            segments.map do |text, color|
              if color
                "#{color}#{text}#{reset}"
              else
                text
              end
            end.join
          end
        end

        def branch_prefix(entries, idx)
          entry = entries[idx]
          level = entry.level
          return '' if level <= 0

          segments = []
          (1..level).each do |depth|
            if depth == level
              segments << (last_child?(entries, idx) ? '└─' : '├─')
            else
              segments << (ancestor_continues?(entries, idx, depth) ? '│ ' : '  ')
            end
          end
          segments.join
        end

        def last_child?(entries, idx)
          current_level = entries[idx].level
          ((idx + 1)...entries.length).each do |i|
            level = entries[i].level
            return false if level == current_level
            return true if level < current_level
          end
          true
        end

        def ancestor_continues?(entries, idx, depth)
          ((idx + 1)...entries.length).each do |i|
            level = entries[i].level
            return true if level == depth
            return false if level < depth
          end
          false
        end

        def entry_icon(entries, idx, entry)
          if entry.level.zero?
            ''
          elsif has_children?(entries, idx)
            ''
          else
            ''
          end
        end

        def has_children?(entries, idx)
          next_entry = entries[idx + 1]
          return false unless next_entry

          next_entry.level > entries[idx].level
        end

        def icon_color_for(entry)
          if entry.level.zero?
            COLOR_TEXT_ACCENT
          elsif entry.level == 1
            COLOR_TEXT_SECONDARY
          else
            COLOR_TEXT_DIM
          end
        end

        def title_color_for(entry)
          if entry.level.zero?
            "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_PRIMARY}"
          elsif entry.level == 1
            COLOR_TEXT_PRIMARY
          else
            COLOR_TEXT_SECONDARY
          end
        end

        def render_footer(surface, bounds, metrics)
          reset = Terminal::ANSI::RESET
          footer_y = metrics.y + metrics.height - 2
          bx = metrics.x
          bw = metrics.width

          divider = "#{COLOR_TEXT_DIM}#{'─' * [bw - 2, 0].max}#{reset}"
          surface.write(bounds, footer_y, bx + 1, divider)

          hints = [
            ['󰆐', 'navigate'],
            ['󰜊', 'jump'],
            ['/', 'filter'],
          ]

          hint_text = hints.map do |icon, label|
            "#{COLOR_TEXT_DIM}#{icon}#{reset} #{COLOR_TEXT_PRIMARY}#{label}#{reset}"
          end.join('  ')

          surface.write(bounds, footer_y + 1, bx + 1, hint_text)
        end
      end
    end
  end
end
