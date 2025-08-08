# frozen_string_literal: true

module EbookReader
  module UI
    # Handles rendering for MainMenu
    class MainMenuRenderer
      include Terminal::ANSI

      def initialize(config)
        @config = config
      end

      def render_logo(height, width)
        logo_start = calculate_logo_position(height)
        draw_logo_lines(logo_start, width)
        draw_version(logo_start + logo_lines.length + 1, width)

        logo_start + logo_lines.length + 5
      end

      MenuItemContext = Struct.new(:row, :pointer_col, :text_col, :item, :selected,
                                   keyword_init: true)

      def render_menu_item(context)
        draw_pointer(context.row, context.pointer_col, context.selected)
        draw_item_text(context)
      end

      def render_footer(height, width, text)
        Terminal.write(height - 1, [(width - text.length) / 2, 1].max,
                       DIM + WHITE + text + RESET)
      end

      # ===== Browse Screen =====
      BrowseContext = Struct.new(
        :height, :width, :selected, :search_query, :search_cursor,
        :filtered_epubs, :scan_status, :scan_message, keyword_init: true
      )

      def render_browse_screen(ctx)
        render_browse_header(ctx.width)
        render_browse_search(ctx.search_query, ctx.search_cursor)
        render_browse_status(ctx.scan_status, ctx.scan_message)

        if ctx.filtered_epubs.nil? || ctx.filtered_epubs.empty?
          render_browse_empty(ctx.height, ctx.width, ctx.scan_status,
                              ctx.filtered_epubs.nil? || ctx.filtered_epubs.empty?)
        else
          render_browse_list(ctx)
        end

        hint = "#{ctx.filtered_epubs&.length.to_i} books • ↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back"
        render_footer(ctx.height, ctx.width, hint)
      end

      def render_browse_header(width)
        Terminal.write(1, 2, "#{BRIGHT_CYAN}📚 Browse Books#{RESET}")
        Terminal.write(1, [width - 30, 40].max, "#{DIM}[r] Refresh [ESC] Back#{RESET}")
      end

      def render_browse_search(query, cursor_pos)
        Terminal.write(3, 2, "#{WHITE}Search: #{RESET}")
        display = (query || '').dup
        cursor_pos = cursor_pos.to_i.clamp(0, display.length)
        display.insert(cursor_pos, '_')
        Terminal.write(3, 10, "#{BRIGHT_WHITE}#{display}#{RESET}")
      end

      def render_browse_status(status, message)
        return if status.nil?

        text = case status
               when :scanning then "#{YELLOW}⟳ #{message}#{RESET}"
               when :error then "#{RED}✗ #{message}#{RESET}"
               when :done then "#{GREEN}✓ #{message}#{RESET}"
               else ''
               end
        Terminal.write(4, 2, text) unless text.empty?
      end

      def render_browse_empty(height, width, status, epubs_empty)
        if status == :scanning
          Terminal.write(height / 2, [(width - 30) / 2, 1].max,
                         "#{YELLOW}⟳ Scanning for books...#{RESET}")
          Terminal.write((height / 2) + 2, [(width - 40) / 2, 1].max,
                         "#{DIM}This may take a moment on first run#{RESET}")
        elsif epubs_empty
          Terminal.write(height / 2, [(width - 30) / 2, 1].max,
                         "#{DIM}No EPUB files found#{RESET}")
          Terminal.write((height / 2) + 2, [(width - 35) / 2, 1].max,
                         "#{DIM}Press [r] to refresh scan#{RESET}")
        else
          Terminal.write(height / 2, [(width - 25) / 2, 1].max,
                         "#{DIM}No matching books#{RESET}")
        end
      end

      def render_browse_list(ctx)
        list_start = 6
        list_height = [ctx.height - 8, 1].max
        visible_start = [ctx.selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, ctx.filtered_epubs.length].min
        range = (visible_start...visible_end)

        range.each_with_index do |idx, row|
          break if row >= list_height
          book = ctx.filtered_epubs[idx]
          next unless book

          name = (book['name'] || 'Unknown')[0, [ctx.width - 40, 40].max]
          row_y = list_start + row
          if idx == ctx.selected
            Terminal.write(row_y, 2, "#{BRIGHT_GREEN}▸ #{RESET}")
            Terminal.write(row_y, 4, BRIGHT_WHITE + name + RESET)
          else
            Terminal.write(row_y, 2, '  ')
            Terminal.write(row_y, 4, WHITE + name + RESET)
          end

          if ctx.width > 60
            path = (book['dir'] || '').sub(Dir.home, '~')
            path = "#{path[0, 30]}..." if path.length > 33
            Terminal.write(row_y, [ctx.width - 35, 45].max, DIM + GRAY + path + RESET)
          end
        end

        return unless ctx.filtered_epubs.length > list_height

        denominator = [ctx.filtered_epubs.length - 1, 1].max
        scroll_pos = ctx.filtered_epubs.length > 1 ? ctx.selected.to_f / denominator : 0
        scroll_row = list_start + (scroll_pos * (list_height - 1)).to_i
        Terminal.write(scroll_row, ctx.width - 2, "#{BRIGHT_CYAN}▐#{RESET}")
      end

      # ===== Recent Screen =====
      RecentContext = Struct.new(:height, :width, :items, :selected, :menu, keyword_init: true)

      def render_recent_screen(ctx)
        Terminal.write(1, 2, "#{BRIGHT_CYAN}🕒 Recent Books#{RESET}")
        Terminal.write(1, [ctx.width - 20, 60].max, "#{DIM}[ESC] Back#{RESET}")

        if ctx.items.empty?
          Terminal.write(ctx.height / 2, [(ctx.width - 20) / 2, 1].max,
                         "#{DIM}No recent books#{RESET}")
        else
          list_start = 4
          max_items = [(ctx.height - 6) / 2, 10].min
          ctx.items.take(max_items).each_with_index do |book, i|
            item_ctx = UI::RecentItemRenderer::Context.new(
              list_start: list_start,
              height: ctx.height,
              width: ctx.width,
              selected_index: ctx.selected
            )
            UI::RecentItemRenderer.new(book: book, index: i, menu: ctx.menu).render(item_ctx)
          end
        end

        Terminal.write(ctx.height - 1, 2,
                       "#{DIM}↑↓ Navigate • Enter Open • ESC Back#{RESET}")
      end

      # ===== Settings Screen =====
      SettingsItem = Struct.new(:key, :name, :value, :action)
      SettingsContext = Struct.new(:height, :width, :items, :status_message, keyword_init: true)

      def render_settings_screen(ctx)
        Terminal.write(1, 2, "#{BRIGHT_CYAN}⚙️  Settings#{RESET}")
        Terminal.write(1, [ctx.width - 20, 60].max, "#{DIM}[ESC] Back#{RESET}")

        start_row = 5
        ctx.items.each_with_index do |setting, i|
          row_base = start_row + (i * 3)
          next if row_base >= ctx.height - 4

          Terminal.write(row_base, 4,
                         "#{YELLOW}[#{setting.key}]#{WHITE} #{setting.name}#{RESET}")
          next unless row_base + 1 < ctx.height - 3

          color = setting.action ? CYAN : BRIGHT_GREEN
          Terminal.write(row_base + 1, 8, color + setting.value + RESET)
        end

        if ctx.status_message && !ctx.status_message.empty?
          row = 5 + (ctx.items.length * 3) + 1
          Terminal.write(row, 4, YELLOW + ctx.status_message + RESET)
        end

        Terminal.write(ctx.height - 3, 4, "#{DIM}Press number keys to toggle settings#{RESET}")
        Terminal.write(ctx.height - 2, 4, "#{DIM}Changes are saved automatically#{RESET}")
      end

      # ===== Open File Screen =====
      OpenFileContext = Struct.new(:height, :width, :input, keyword_init: true)

      def render_open_file_screen(ctx)
        Terminal.write(1, 2, "#{BRIGHT_CYAN}󰷏 Open File#{RESET}")
        Terminal.write(1, [ctx.width - 20, 60].max, "#{DIM}[ESC] Cancel#{RESET}")

        prompt = 'Enter EPUB path: '
        col = [(ctx.width - prompt.length - 40) / 2, 2].max
        row = ctx.height / 2
        Terminal.write(row, col, WHITE + prompt + RESET)
        Terminal.write(row, col + prompt.length, "#{BRIGHT_WHITE}#{ctx.input}_#{RESET}")

        footer = 'Enter to open • Backspace delete • ESC cancel'
        Terminal.write(ctx.height - 1, 2, DIM + footer + RESET)
      end

      # ===== Annotations Screen =====
      AnnotationsContext = Struct.new(
        :height, :width, :books, :annotations_by_book,
        :selected_book_index, :selected_annotation_index,
        :popup, keyword_init: true
      )

      PopupContext = Struct.new(:title, :text, :visible, keyword_init: true)

      def render_annotations_screen(ctx)
        if ctx.popup&.visible
          render_annotation_popup(ctx)
          return
        end

        Terminal.write(1, 2, BOLD + 'All Annotations' + RESET)
        Terminal.write(2, 0, DIM + ('─' * ctx.width) + RESET)

        row = 4
        ctx.books.each_with_index do |book_path, i|
          break if row > ctx.height - 3

          book_title = File.basename(book_path.to_s, '.epub')
          if i == ctx.selected_book_index
            Terminal.write(row, 2, BRIGHT_BLUE + '‣ ' + book_title + RESET)
            row += 1

            (ctx.annotations_by_book[book_path] || []).each_with_index do |annotation, j|
              break if row > ctx.height - 3
              render_annotation_item(annotation, j, row, ctx.width,
                                     j == ctx.selected_annotation_index)
              row += 2
            end
          else
            Terminal.write(row, 2, '  ' + book_title)
            row += 1
          end

          row += 1
        end

        footer_text = '↑↓/jk: Navigate | Enter: Edit | d: Delete | q: Back'
        Terminal.write(ctx.height, 2, DIM + footer_text + RESET)
        Terminal.write(ctx.height - 1, 0, DIM + ('─' * ctx.width) + RESET)
      end

      def render_annotation_item(annotation, index, row, width, selected)
        text = annotation['text'].to_s.tr("\n", ' ').strip
        note = annotation['note'].to_s.tr("\n", ' ').strip
        pointer = selected ? YELLOW + '→' + RESET : ' '

        display_text = "  #{pointer} #{ITALIC}\"#{text[0, width - 15]}\"...#{RESET}"
        display_note = "      #{DIM}#{note[0, width - 15]}...#{RESET}"

        Terminal.write(row, 4, display_text)
        Terminal.write(row + 1, 4, display_note)
      end

      def render_annotation_popup(ctx)
        popup = ctx.popup
        return unless popup&.visible

        popup_height = [[10, (popup.text || '').lines.count + 4].min, 4].max
        popup_width = [60, ctx.width - 10].min

        start_y = (ctx.height - popup_height) / 2
        start_x = (ctx.width - popup_width) / 2

        # Shadow/background
        (start_y...(start_y + popup_height)).each do |y|
          Terminal.write(y, start_x, BG_GREY + (' ' * popup_width) + RESET)
        end

        # Title
        Terminal.write(start_y, start_x + 2, BRIGHT_WHITE + popup.title.to_s[0, popup_width - 4] + RESET)

        # Text
        (popup.text || '').lines.each_with_index do |line, i|
          break if i > popup_height - 4
          Terminal.write(start_y + 2 + i, start_x + 2, WHITE + line.strip[0, popup_width - 4] + RESET)
        end

        hint = DIM + 'Enter/ESC to close' + RESET
        Terminal.write(start_y + popup_height - 1, start_x + 2, hint)
      end

      private

      def logo_lines
        @logo_lines ||= [
          '    ____                __         ',
          '   / __ \___  ____ _____/ /__  _____',
          '  / /_/ / _ \/ __ `/ __  / _ \/ ___/',
          ' / _, _/  __/ /_/ / /_/ /  __/ /    ',
          '/_/ |_|\___/\__,_/\__,_/\___/_/     ',
          '                                     ',
        ]
      end

      def calculate_logo_position(height)
        [((height - logo_lines.length - 15) / 2), 2].max
      end

      def draw_logo_lines(start_row, width)
        logo_lines.each_with_index do |line, i|
          col = [(width - line.length) / 2, 1].max
          Terminal.write(start_row + i, col, CYAN + line + RESET)
        end
      end

      def draw_version(row, width)
        version_text = "version #{VERSION}"
        Terminal.write(row, (width - version_text.length) / 2,
                       DIM + WHITE + version_text + RESET)
      end

      def draw_pointer(row, col, selected)
        pointer = selected ? "#{BRIGHT_GREEN}▸ #{RESET}" : '  '
        Terminal.write(row, col, pointer)
      end

      def draw_item_text(context)
        text = format_menu_item_text(context.item, context.selected)
        Terminal.write(context.row, context.text_col, text)
      end

      def format_menu_item_text(item, selected)
        if selected
          "#{BRIGHT_WHITE}#{item[:icon]}  #{BRIGHT_YELLOW}[#{item[:key]}]" \
            "#{BRIGHT_WHITE} #{item[:text]}#{GRAY} — #{item[:desc]}#{RESET}"
        else
          "#{WHITE}#{item[:icon]}  #{YELLOW}[#{item[:key]}]" \
            "#{WHITE} #{item[:text]}#{DIM}#{GRAY} — #{item[:desc]}#{RESET}"
        end
      end
    end
  end
end
