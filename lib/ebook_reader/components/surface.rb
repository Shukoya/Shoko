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
        return if bounds.height <= 0 || bounds.width <= 0

        abs_row = bounds.y + row - 1
        abs_col = bounds.x + col - 1

        return if abs_row < bounds.y || abs_row > bounds.bottom
        return if abs_col > bounds.right

        max_width = bounds.right - abs_col + 1
        clipped = text.to_s[0, max_width]
        return if clipped.nil? || clipped.empty?

        @output.write(abs_row, abs_col, clipped)
      end

      # Convenience to fill an area with a character
      def fill(bounds, char)
        line = char.to_s * bounds.width
        (0...bounds.height).each do |r|
          write(bounds, r + 1, 1, line)
        end
      end
    end
  end
end

