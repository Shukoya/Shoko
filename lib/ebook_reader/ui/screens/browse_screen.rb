# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Handles browse screen rendering
      class BrowseScreen
        include Terminal::ANSI

        BROWSE_FOOTER_HINTS = '↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back'

        attr_accessor :selected, :search_query, :search_cursor, :filtered_epubs

        def initialize(scanner)
          @scanner = scanner
          @selected = 0
          @search_query = ''
          @search_cursor = 0
          @filtered_epubs = []
        end

        def draw(height, width)
          render_header(width)
          render_search_bar(@search_query, @search_cursor)
          render_status(@scanner.scan_status, @scanner.scan_message)

          if @filtered_epubs.empty?
            render_empty_state(EmptyStateContext.new(height: height, width: width,
                                                     scan_status: @scanner.scan_status,
                                                     epubs_empty: @scanner.epubs.empty?))
          else
            render_book_list(height, width)
          end

          render_footer(height, width)
        end

        def render_header(width)
          Terminal.write(1, 2, "#{BRIGHT_CYAN}📚 Browse Books#{RESET}")
          Terminal.write(1, [width - 30, 40].max, "#{DIM}[r] Refresh [ESC] Back#{RESET}")
        end

        def render_search_bar(search_query, cursor_pos)
          Terminal.write(3, 2, "#{WHITE}Search: #{RESET}")
          display = search_query.dup
          cursor_pos = [[cursor_pos, 0].max, display.length].min
          display.insert(cursor_pos, '_')
          Terminal.write(3, 10, "#{BRIGHT_WHITE}#{display}#{RESET}")
        end

        def render_status(scan_status, scan_message)
          status_text = build_status_text(scan_status, scan_message)
          Terminal.write(4, 2, status_text) unless status_text.empty?
        end

        def build_status_text(status, message)
          status_formatters[status]&.call(message) || ''
        end

        def status_formatters
          @status_formatters ||= {
            scanning: ->(msg) { "#{YELLOW}⟳ #{msg}#{RESET}" },
            error: ->(msg) { "#{RED}✗ #{msg}#{RESET}" },
            done: ->(msg) { "#{GREEN}✓ #{msg}#{RESET}" },
          }
        end

        EmptyStateContext = Struct.new(:height, :width, :scan_status, :epubs_empty,
                                       keyword_init: true)

        def render_empty_state(context)
          if context.scan_status == :scanning
            render_scanning_message(context.height, context.width)
          elsif context.epubs_empty
            render_no_files_message(context.height, context.width)
          else
            render_no_matches_message(context.height, context.width)
          end
        end

        def render_book_list(height, width)
          list_start = 6
          list_height = [height - 8, 1].max

          visible_range = calculate_visible_range(list_height)
          metrics = { list_start: list_start, list_height: list_height, width: width }
          render_visible_books(visible_range, metrics)
          return unless @filtered_epubs.length > list_height

          render_scroll_indicator(list_start, list_height, width)
        end

        def render_footer(height, _width)
          hint = "#{@filtered_epubs.length} books • #{BROWSE_FOOTER_HINTS}"
          Terminal.write(height - 1, 2, "#{DIM}#{hint}#{RESET}")
        end

        private

        def calculate_visible_range(list_height)
          visible_start = [@selected - (list_height / 2), 0].max
          visible_end = [visible_start + list_height, @filtered_epubs.length].min

          if visible_end == @filtered_epubs.length && @filtered_epubs.length > list_height
            visible_start = [visible_end - list_height, 0].max
          end

          visible_start...visible_end
        end

        def render_visible_books(range, metrics)
          list_start = metrics[:list_start]
          list_height = metrics[:list_height]
          width = metrics[:width]

          range.each_with_index do |idx, row|
            next if row >= list_height

            book = @filtered_epubs[idx]
            next unless book

            render_book_item(book, idx, row: list_start + row, width: width)
          end
        end

        def render_book_item(book, idx, row:, width:)
          name = (book['name'] || 'Unknown')[0, [width - 40, 40].max]

          if idx == @selected
            Terminal.write(row, 2, "#{BRIGHT_GREEN}▸ #{RESET}")
            Terminal.write(row, 4, BRIGHT_WHITE + name + RESET)
          else
            Terminal.write(row, 2, '  ')
            Terminal.write(row, 4, WHITE + name + RESET)
          end

          render_book_path(book, row, width) if width > 60
        end

        def render_book_path(book, row, width)
          path = (book['dir'] || '').sub(Dir.home, '~')
          path = "#{path[0, 30]}..." if path.length > 33
          Terminal.write(row, [width - 35, 45].max,
                         DIM + GRAY + path + RESET)
        end

        def render_scroll_indicator(list_start, list_height, width)
          denominator = [@filtered_epubs.length - 1, 1].max
          scroll_pos = @filtered_epubs.length > 1 ? @selected.to_f / denominator : 0
          scroll_row = list_start + (scroll_pos * (list_height - 1)).to_i
          Terminal.write(scroll_row, width - 2, "#{BRIGHT_CYAN}▐#{RESET}")
        end

        def render_scanning_message(height, width)
          Terminal.write(height / 2, [(width - 30) / 2, 1].max,
                         "#{YELLOW}⟳ Scanning for books...#{RESET}")
          Terminal.write((height / 2) + 2, [(width - 40) / 2, 1].max,
                         "#{DIM}This may take a moment on first run#{RESET}")
        end

        def render_no_files_message(height, width)
          Terminal.write(height / 2, [(width - 30) / 2, 1].max,
                         "#{DIM}No EPUB files found#{RESET}")
          Terminal.write((height / 2) + 2, [(width - 35) / 2, 1].max,
                         "#{DIM}Press [r] to refresh scan#{RESET}")
        end

        def render_no_matches_message(height, width)
          Terminal.write(height / 2, [(width - 25) / 2, 1].max,
                         "#{DIM}No matching books#{RESET}")
        end
      end
    end
  end
end
