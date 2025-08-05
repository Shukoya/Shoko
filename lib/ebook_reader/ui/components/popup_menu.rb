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

        def contains?(x, y)
          x >= @x && x < (@x + @width) && 
          y >= @y && y < (@y + @height)
        end

        private

        def calculate_width
          @items.map(&:length).max + 4
        end

        def draw_shadow
          # Draw subtle shadow
          (0...@height).each do |i|
            Terminal.write(@y + i + 1, @x + 1, ' ' * @width)
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
          
          bg = is_selected ? Terminal::ANSI::GREEN : Terminal::ANSI::BG_DARK
          fg = is_selected ? Terminal::ANSI::BLACK : Terminal::ANSI::WHITE
          
          line_text = " #{item} ".ljust(@width)
          
          Terminal.write(item_y, @x, 
            "#{bg}#{fg}#{line_text}#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
