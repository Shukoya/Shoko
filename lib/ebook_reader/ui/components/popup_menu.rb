# frozen_string_literal: true

module EbookReader
  module UI
    module Components
      # Floating popup menu for selected text
      class PopupMenu
        attr_reader :visible, :selected_index, :x, :y

        def initialize(x, y, items)
          @x = x
          @y = y
          @items = items
          @selected_index = 0
          @visible = true
          @width = calculate_width
          @height = @items.length
        end

        def render
          return unless @visible

          draw_shadow
          draw_menu_items
        end

        def move_selection(direction)
          @selected_index = (@selected_index + direction) % @items.length
        end

        def get_selected_item
          @items[@selected_index]
        end

        def hide
          @visible = false
        end

        def handle_click(click_x, click_y)
          return nil unless @visible && contains?(click_x, click_y)

          clicked_index = click_y - @y
          return nil unless clicked_index >= 0 && clicked_index < @items.length

          @selected_index = clicked_index
          get_selected_item
        end

        def handle_key(key)
          case
          when Terminal::Keys::UP.include?(key)
            move_selection(-1)
            return { type: :selection_change }
          when Terminal::Keys::DOWN.include?(key)
            move_selection(1)
            return { type: :selection_change }
          when Terminal::Keys::ENTER.include?(key)
            return { type: :confirm, item: get_selected_item }
          when Terminal::Keys::ESCAPE.include?(key)
            return { type: :cancel }
          end
          nil
        end

        def contains?(x, y)
          x >= @x && x < (@x + @width) &&
            y >= @y && y < (@y + @height)
        end

        private

        def calculate_width
          @items.map(&:length).max + 4
        end

        def draw_shadow
          # A more subtle, modern shadow
          (0...@height).each do |i|
            Terminal.write(@y + i + 1, @x + 1,
                           "#{Terminal::ANSI::BG_GREY} #{Terminal::ANSI::RESET}" * @width)
          end
        end

        def draw_menu_items
          @items.each_with_index do |item, i|
            draw_menu_item(item, i)
          end
        end

        def draw_menu_item(item, index)
          item_y = @y + index
          is_selected = (index == @selected_index)

          # Modern, flat design with better contrast
          bg = is_selected ? Terminal::ANSI::BLUE : Terminal::ANSI::BG_BLACK
          fg = is_selected ? Terminal::ANSI::WHITE : Terminal::ANSI::LIGHT_GREY

          # Clear the line with the background color first
          Terminal.write(item_y, @x, "#{bg}#{' ' * @width}#{Terminal::ANSI::RESET}")

          # Render the text with an icon
          icon = is_selected ? '❯' : ' '
          line_text = " #{icon} #{item} ".ljust(@width)

          Terminal.write(item_y, @x, "#{bg}#{fg}#{line_text}#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
