# frozen_string_literal: true

require_relative '../../terminal'

module EbookReader
  module UI
    module Components
      class Popup
        def initialize(title, text)
          @title = title
          @text = text
          @visible = true
        end

        def draw(height, width)
          return unless @visible

          popup_height = [10, @text.lines.count + 4].min
          popup_width = [60, width - 10].min

          start_y = (height - popup_height) / 2
          start_x = (width - popup_width) / 2

          # Draw border
          (start_y...(start_y + popup_height)).each do |y|
            Terminal.write(y, start_x, ' ' * popup_width)
          end

          # Draw title
          Terminal.write(start_y, start_x + 2, @title)

          # Draw text
          @text.lines.each_with_index do |line, i|
            break if i > popup_height - 4

            Terminal.write(start_y + 2 + i, start_x + 2, line.strip)
          end
        end

        def handle_input(key)
          @visible = false if ["\e", "\r"].include?(key)
        end

        def visible?
          @visible
        end
      end
    end
  end
end
