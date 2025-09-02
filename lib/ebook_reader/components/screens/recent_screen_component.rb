# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../../recent_files'
require 'time'

module EbookReader
  module Components
    module Screens
      # Component-based renderer for the recent books screen
      class RecentScreenComponent < BaseScreenComponent
        include EbookReader::Constants

        def initialize(main_menu, state)
          super()
          @main_menu = main_menu
          @state = state
        end

        # Setter method for selection index (used by input handlers)
        def selected=(index)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: index))
          invalidate
        end

        def do_render(surface, bounds)
          items = load_recent_books
          selected = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty_state(surface, bounds)
          else
            render_recent_list(surface, bounds, items, selected)
          end

          render_footer(surface, bounds)
        end

        private

        def render_header(surface, bounds)
          write_header(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_ACCENT}🕒 Recent Books#{Terminal::ANSI::RESET}",
            "#{UIConstants::COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}"
          )
        end

        def render_empty_state(surface, bounds)
          write_empty_message(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_DIM}No recent books#{Terminal::ANSI::RESET}"
          )
        end

        def render_recent_list(surface, bounds, items, selected)
          list_start = 4
          list_height = bounds.height - list_start - 2
          return if list_height <= 0

          # Header + divider
          draw_list_header(surface, bounds, bounds.width, list_start)
          list_start += 2
          list_height -= 2

          items_per_page = list_height
          start_index, visible_items = calculate_visible_range(items.length, items_per_page,
                                                               selected)

          loading_path = @state.get(%i[menu loading_path])
          loading_active = @state.get(%i[menu loading_active])
          loading_progress = (@state.get(%i[menu loading_progress]) || 0.0).to_f

          current_row = list_start
          visible_items.each_with_index do |book, i|
            break if current_row >= bounds.height - 1

            render_recent_item(surface, bounds, current_row, bounds.width, book, start_index + i,
                               selected)
            if loading_active && loading_path == book['path'] && current_row + 1 < bounds.height - 1
              draw_inline_progress(surface, bounds, bounds.width, current_row + 1, loading_progress)
              current_row += 2
            else
              current_row += 1
            end
          end
        end

        def calculate_visible_range(total_items, per_page, selected)
          start_index = 0

          start_index = selected - per_page + 1 if selected >= per_page

          start_index = [start_index, total_items - per_page].min if total_items > per_page

          end_index = [start_index + per_page - 1, total_items - 1].min
          [start_index, load_recent_books[start_index..end_index] || []]
        end

        def render_recent_item(surface, bounds, row, width, book, index, selected)
          is_selected = (index == selected)
          @meta_cache ||= {}

          path = book['path']
          size_bytes = begin
            File.size(path)
          rescue StandardError
            0
          end
          meta = @meta_cache[path]
          unless meta
            require_relative '../../helpers/metadata_extractor'
            meta = Helpers::MetadataExtractor.from_epub(path)
            @meta_cache[path] = meta
          end

          title = (meta[:title] || book['name'] || 'Unknown').to_s
          authors = (meta[:author_str] || '').to_s
          year = (meta[:year] || '').to_s
          accessed = relative_accessed_label(book['accessed'])
          size_mb = format_size(size_bytes)

          # Columns like Browse
          pointer_w = 2
          gap = 2
          remaining = width - pointer_w - (gap * 4)
          year_w = 6
          last_w = 16
          size_w = 8
          author_w = [[(remaining * 0.25).to_i, 12].max,
                      remaining - 20 - year_w - last_w - size_w].min
          title_w = [remaining - author_w - year_w - last_w - size_w, 20].max

          pointer = is_selected ? '▸ ' : '  '
          title_col = truncate_text(title, title_w).ljust(title_w)
          author_col = truncate_text(authors, author_w).ljust(author_w)
          year_col = year[0, 4].ljust(year_w)
          last_col = truncate_text(accessed, last_w).ljust(last_w)
          size_col = size_mb.rjust(size_w)

          line = [title_col, author_col, year_col, last_col, size_col].join(' ' * gap)
          if is_selected
            surface.write(bounds, row, 1, UIConstants::SELECTION_HIGHLIGHT + pointer + line + Terminal::ANSI::RESET)
          else
            surface.write(bounds, row, 1, UIConstants::COLOR_TEXT_PRIMARY + pointer + line + Terminal::ANSI::RESET)
          end
        end

        def draw_list_header(surface, bounds, width, row)
          pointer_w = 2
          gap = 2
          remaining = width - pointer_w - (gap * 4)
          year_w = 6
          last_w = 16
          size_w = 8
          author_w = [[(remaining * 0.25).to_i, 12].max,
                      remaining - 20 - year_w - last_w - size_w].min
          title_w = [remaining - author_w - year_w - last_w - size_w, 20].max

          headers = [
            'Title'.ljust(title_w),
            'Author(s)'.ljust(author_w),
            'Year'.ljust(year_w),
            'Last accessed'.ljust(last_w),
            'Size'.rjust(size_w),
          ].join(' ' * gap)
          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::LIGHT_GREY
          surface.write(bounds, row, 1, header_style + (' ' * pointer_w) + headers + Terminal::ANSI::RESET)
          # Divider line
          divider = ('─' * [width - 2, 1].max)
          surface.write(bounds, row + 1, 1, UIConstants::COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def format_size(bytes)
          mb = (bytes.to_f / (1024 * 1024)).round(1)
          format('%.1f MB', mb)
        end

        def truncate_text(text, max_length)
          str = text.to_s
          return str if str.length <= max_length

          "#{str[0...(max_length - 3)]}..."
        end

        def relative_accessed_label(iso)
          return '' unless iso

          t = begin
            Time.parse(iso)
          rescue StandardError
            nil
          end
          return '' unless t

          seconds = (Time.now - t).to_i
          minutes = seconds / 60
          hours = seconds / 3600
          days = seconds / 86_400
          weeks = days / 7

          if hours < 1
            minutes <= 1 ? 'a minute ago' : "#{minutes} minutes ago"
          elsif days < 1
            hours == 1 ? 'an hour ago' : "#{hours} hours ago"
          elsif days == 1
            'yesterday'
          elsif days < 7
            days == 1 ? 'a day ago' : "#{days} days ago"
          else
            weeks == 1 ? 'a week ago' : "#{weeks} weeks ago"
          end
        end

        def draw_inline_progress(surface, bounds, width, row, progress)
          bar_col = 3
          usable = [width - bar_col - 2, 10].max
          filled = (usable * progress.to_f.clamp(0.0, 1.0)).round
          green = Terminal::ANSI::BRIGHT_GREEN
          grey  = Terminal::ANSI::GRAY
          reset = Terminal::ANSI::RESET
          track = (green + ('━' * filled)) + (grey + ('━' * (usable - filled))) + reset
          surface.write(bounds, row, bar_col, track)
        end

        def render_footer(surface, bounds)
          write_footer(
            surface, bounds,
            "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}"
          )
        end

        def load_recent_books
          RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
        end

        # no-op placeholder removed; relative_accessed_label is used instead
      end
    end
  end
end
