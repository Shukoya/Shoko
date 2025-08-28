# frozen_string_literal: true

require_relative '../base_component'
require_relative '../rect'

module EbookReader
  module Components
    module Layouts
      # Horizontal layout that splits children left-to-right
      # Supports collapsible left sidebar with dynamic width allocation
      class Horizontal
        def initialize(left_child, right_child)
          @left_child = left_child
          @right_child = right_child
        end

        def render(surface, bounds)
          return unless @left_child && @right_child

          # Calculate widths based on left child's preferred width
          left_width = calculate_left_width(bounds.width)
          right_width = bounds.width - left_width

          # Render left child (sidebar)
          if left_width.positive?
            left_bounds = Rect.new(x: bounds.x, y: bounds.y, width: left_width,
                                   height: bounds.height)
            @left_child.render(surface, left_bounds)
          end

          # Render right child (content)
          return unless right_width.positive?

          right_x = bounds.x + left_width
          right_bounds = Rect.new(x: right_x, y: bounds.y, width: right_width,
                                  height: bounds.height)
          @right_child.render(surface, right_bounds)
        end

        private

        def calculate_left_width(total_width)
          return 0 unless @left_child.respond_to?(:preferred_width)

          pref = @left_child.preferred_width(total_width)
          case pref
          when Integer
            [pref, total_width].min
          when :hidden
            0
          when :flexible
            total_width / 3 # Default to 1/3 width
          else
            0
          end
        end
      end
    end
  end
end
