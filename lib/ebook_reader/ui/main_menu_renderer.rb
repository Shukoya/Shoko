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
        draw_item_text(context.row, context.text_col, context.item, context.selected)
      end

      def render_footer(height, width, text)
        Terminal.write(height - 1, [(width - text.length) / 2, 1].max,
                       DIM + WHITE + text + RESET)
      end

      private

      def logo_lines
        @logo_lines ||= [
          '    ____                __         ',
          '   / __ \\___  ____ _____/ /__  _____',
          '  / /_/ / _ \\/ __ `/ __  / _ \\/ ___/',
          ' / _, _/  __/ /_/ / /_/ /  __/ /    ',
          '/_/ |_|\\___/\\__,_/\\__,_/\\___/_/     ',
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

      def draw_item_text(row, col, item, selected)
        text = format_menu_item_text(item, selected)
        Terminal.write(row, col, text)
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
