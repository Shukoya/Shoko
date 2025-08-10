# frozen_string_literal: true

require_relative '../base_component'
require_relative '../rect'

module EbookReader
  module Components
    module Layouts
      # Simple vertical layout that stacks children top-to-bottom
      # Respects preferred heights; assigns remaining space to first flexible child
      class Vertical
        def initialize(children)
          @children = children
        end

        def render(surface, bounds)
          return if @children.nil? || @children.empty?

          # Determine heights
          fixed_heights = []
          flex_index = nil
          remaining = bounds.height

          @children.each_with_index do |child, i|
            pref = child.respond_to?(:preferred_height) ? child.preferred_height(remaining) : nil
            if pref&.positive?
              fixed_heights[i] = pref
              remaining -= pref
            else
              flex_index ||= i
              fixed_heights[i] = nil
            end
          end

          # Assign remaining to first flex child
          fixed_heights[flex_index] = [remaining, 0].max if flex_index

          # Render children
          cursor_y = bounds.y
          @children.each_with_index do |child, i|
            height = fixed_heights[i] || 0
            next if height <= 0

            child_bounds = Rect.new(x: bounds.x, y: cursor_y, width: bounds.width, height: height)
            child.render(surface, child_bounds)
            cursor_y += height
          end
        end
      end
    end
  end
end
