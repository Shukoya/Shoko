# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../ui/list_helpers'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Reading
      # Renderer for table of contents display
      class TocRenderer < BaseViewRenderer
        ItemCtx = Struct.new(:chapter, :index, :selected_index, :y, keyword_init: true)
        def render_with_context(surface, bounds, context)
          st = context&.state
          doc = context&.document
          return unless st && doc

          selected_entry_index = (st.get(%i[reader toc_selected]) || 0).to_i
          entries = doc.respond_to?(:toc_entries) ? doc.toc_entries : []
          entries = fallback_entries(doc.chapters) if entries.nil? || entries.empty?

          selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)

          render_header(surface, bounds)
          render_entries_list(surface, bounds, entries, selected_entry_index)
          render_footer(surface, bounds)
        end

        private

        EntryCtx = Struct.new(:entry, :index, :selected_entry_index, :y,
                              keyword_init: true)

        def render_header(surface, bounds)
          w = bounds.width
          reset = Terminal::ANSI::RESET
          surface.write(bounds, 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT}📖 Table of Contents#{reset}")
          surface.write(bounds, 1, [w - 30, 40].max,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}[t/ESC] Back to Reading#{reset}")
        end

        def render_entries_list(surface, bounds, entries, selected_entry_index)
          return if entries.empty?

          list_start = 4
          list_height = bounds.height - 6

          window_start, items = EbookReader::Components::UI::ListHelpers.slice_visible(entries,
                                                                                       list_height,
                                                                                       selected_entry_index)
          items.each_with_index do |entry, row|
            idx = window_start + row
            y = list_start + row
            ctx = EntryCtx.new(entry: entry,
                               index: idx,
                               selected_entry_index: selected_entry_index,
                               y: y)
            render_entry(surface, bounds, ctx)
          end
        end

        def render_entry(surface, bounds, ctx)
          entry = ctx.entry
          reset = Terminal::ANSI::RESET
          width = bounds.width
          title = entry_title(entry)
          indent = '  ' * [entry.level, 0].max
          available = [width - 4, 1].max
          display = EbookReader::Helpers::TextMetrics.truncate_to(indent + title, available, start_column: 3)

          selected = ctx.index == ctx.selected_entry_index
          pointer = if selected
                      EbookReader::Constants::UIConstants::SELECTION_POINTER_COLOR + EbookReader::Constants::UIConstants::SELECTION_POINTER + reset
                    else
                      '  '
                    end

          base_color = if entry.level.zero?
                         EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT
                       elsif entry.navigable
                         EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY
                       else
                         EbookReader::Constants::UIConstants::COLOR_TEXT_DIM
                       end

          line_text = if selected
                        EbookReader::Constants::UIConstants::SELECTION_HIGHLIGHT + display + reset
                      else
                        base_color + display + reset
                      end

          pointer_text = if selected
                           pointer
                         elsif entry.navigable
                           "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}○ #{reset}"
                         else
                           '  '
                         end

          surface.write(bounds, ctx.y, 2, pointer_text)
          surface.write(bounds, ctx.y, 4, line_text)
        end

        def entry_title(entry)
          title = entry.title || 'Untitled'
          entry.level.zero? ? title.upcase : title
        end

        def fallback_entries(chapters)
          chapters.each_with_index.map do |chapter, idx|
            Domain::Models::TOCEntry.new(title: chapter.title || "Chapter #{idx + 1}",
                                         href: nil,
                                         level: 0,
                                         chapter_index: idx,
                                         navigable: true)
          end
        end

        def render_footer(surface, bounds)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, bounds.height - 1, 2,
                        "#{EbookReader::Constants::UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{reset}")
        end
      end
    end
  end
end
