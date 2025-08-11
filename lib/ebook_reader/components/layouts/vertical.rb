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

          # Calculate heights using new contract
          heights = calculate_child_heights(bounds.height)

          # Render children
          cursor_y = bounds.y
          @children.each_with_index do |child, i|
            height = heights[i] || 0
            next if height <= 0

            child_bounds = Rect.new(x: bounds.x, y: cursor_y, width: bounds.width, height: height)
            child.render(surface, child_bounds)
            cursor_y += height
          end
        end

        private

        def calculate_child_heights(total_height)
          heights = []
          remaining = total_height
          fill_children = []

          # First pass: allocate fixed heights
          @children.each_with_index do |child, i|
            pref = child.respond_to?(:preferred_height) ? child.preferred_height(total_height) : :flexible

            case pref
            when Integer
              # Fixed height
              height = [pref, remaining].min
              heights[i] = height
              remaining -= height
            when :fill
              # Fill remaining space (calculated in second pass)
              fill_children << i
              heights[i] = nil
            when :flexible
              # Use minimum space for now, will expand if needed
              heights[i] = 0
            else
              heights[i] = 0
            end
          end

          # Second pass: distribute remaining space to fill children
          if fill_children.any? && remaining.positive?
            fill_height = remaining / fill_children.size
            fill_children.each { |i| heights[i] = fill_height }
          elsif fill_children.any?
            # No remaining space for fill children
            fill_children.each { |i| heights[i] = 0 }
          end

          heights
        end
      end
    end
  end
end
