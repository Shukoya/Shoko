# frozen_string_literal: true

require_relative '../terminal'

module EbookReader
  module Components
    # Terminal wrapper that applies bounds and basic clipping
    class Surface
      def initialize(output = Terminal)
        @output = output
      end

      # Write text at local (row, col) relative to bounds
      # Applies basic clipping to the provided bounds
      def write(bounds, row, col, text)
        b_height = bounds.height
        b_width  = bounds.width
        return if b_height <= 0 || b_width <= 0

        b_y = bounds.y
        b_x = bounds.x
        b_right = bounds.right
        b_bottom = bounds.bottom

        abs_row = b_y + row - 1
        abs_col = b_x + col - 1

        return if abs_row < b_y || abs_row > b_bottom
        return if abs_col > b_right

        max_width = b_right - abs_col + 1
        clipped = text.to_s[0, max_width]
        return if clipped.nil? || clipped.empty?

        @output.write(abs_row, abs_col, clipped)
      end

      # Convenience to fill an area with a character
      def fill(bounds, char)
        w = bounds.width
        h = bounds.height
        line = char.to_s * w
        (0...h).each do |r|
          write(bounds, r + 1, 1, line)
        end
      end
    end
  end
end
