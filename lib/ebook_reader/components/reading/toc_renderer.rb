# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../ui/list_helpers'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Reading
      # Renderer for table of contents display
      class TocRenderer < BaseViewRenderer
        # Internal context object for rendering a single TOC entry row.
        EntryCtx = Struct.new(:entry, :index, :selected_entry_index, :row, keyword_init: true)
        private_constant :EntryCtx

        def render_with_context(surface, bounds, context)
          state = context&.state
          document = context&.document
          return unless state && document

          entries = toc_entries(document)
          selected_entry_index = selected_entry_index(state, entries.length)

          render_header(surface, bounds)
          render_entries_list(surface, bounds, entries, selected_entry_index)
          render_footer(surface, bounds)
        end

        private

        def toc_entries(document)
          entries = document.respond_to?(:toc_entries) ? document.toc_entries : []
          return entries unless entries.nil? || entries.empty?

          fallback_entries(document.chapters)
        end

        def selected_entry_index(state, entries_count)
          index = (state.get(%i[reader toc_selected]) || 0).to_i
          max_index = [entries_count - 1, 0].max
          index.clamp(0, max_index)
        end

        def render_header(surface, bounds)
          width = bounds.width
          reset = Terminal::ANSI::RESET
          surface.write(
            bounds,
            1,
            2,
            "#{EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT}📖 Table of Contents#{reset}"
          )
          surface.write(
            bounds,
            1,
            [width - 30, 40].max,
            "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}[t/ESC] Back to Reading#{reset}"
          )
        end

        def render_entries_list(surface, bounds, entries, selected_entry_index)
          return if entries.empty?

          list_start_row = 4
          list_height = bounds.height - 6

          window_start, items = EbookReader::Components::UI::ListHelpers.slice_visible(
            entries,
            list_height,
            selected_entry_index
          )

          items.each_with_index do |entry, offset|
            idx = window_start + offset
            row = list_start_row + offset
            ctx = EntryCtx.new(entry: entry, index: idx, selected_entry_index: selected_entry_index, row: row)
            render_entry(surface, bounds, ctx)
          end
        end

        def render_entry(surface, bounds, ctx)
          entry = ctx.entry
          reset = Terminal::ANSI::RESET
          width = bounds.width

          entry_level = entry.level
          navigable = entry.navigable
          display = entry_display_text(entry, width, bounds, entry_level)
          base_color = entry_color(entry_level, navigable)

          selected = ctx.index == ctx.selected_entry_index
          surface.write(bounds, ctx.row, 2, pointer_text(navigable, selected, reset))
          surface.write(bounds, ctx.row, 4, line_text(display, selected, base_color, reset))
        end

        def entry_display_text(entry, width, bounds, entry_level)
          title = entry_title(entry, entry_level)
          indent = '  ' * [entry_level, 0].max
          available = [width - 4, 1].max
          EbookReader::Helpers::TextMetrics.truncate_to(
            indent + title,
            available,
            start_column: bounds.x + 2
          )
        end

        def entry_title(entry, entry_level)
          title = entry.title || 'Untitled'
          entry_level.zero? ? title.upcase : title
        end

        def pointer_text(navigable, selected, reset)
          return selection_pointer_text(reset) if selected
          return navigable_pointer_text(reset) if navigable

          '  '
        end

        def selection_pointer_text(reset)
          color = EbookReader::Constants::UIConstants::SELECTION_POINTER_COLOR
          pointer = EbookReader::Constants::UIConstants::SELECTION_POINTER
          "#{color}#{pointer}#{reset}"
        end

        def navigable_pointer_text(reset)
          "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}○ #{reset}"
        end

        def line_text(display, selected, base_color, reset)
          color = selected ? EbookReader::Constants::UIConstants::SELECTION_HIGHLIGHT : base_color
          "#{color}#{display}#{reset}"
        end

        def entry_color(entry_level, navigable)
          if entry_level.zero?
            EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT
          elsif navigable
            EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY
          else
            EbookReader::Constants::UIConstants::COLOR_TEXT_DIM
          end
        end

        def fallback_entries(chapters)
          chapters.each_with_index.map do |chapter, idx|
            Domain::Models::TOCEntry.new(
              title: chapter.title || "Chapter #{idx + 1}",
              href: nil,
              level: 0,
              chapter_index: idx,
              navigable: true
            )
          end
        end

        def render_footer(surface, bounds)
          reset = Terminal::ANSI::RESET
          footer = "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}" \
                   "↑↓ Navigate • Enter Jump • t/ESC Back#{reset}"
          surface.write(bounds, bounds.height - 1, 2, footer)
        end
      end
    end
  end
end
