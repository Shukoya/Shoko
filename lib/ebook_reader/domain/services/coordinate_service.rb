# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Domain service for coordinate system management with dependency injection.
      # Migrated from legacy Services::CoordinateService to follow DI pattern.
      class CoordinateService < BaseService
        # Convert mouse coordinates (0-based) to terminal coordinates (1-based)
        def mouse_to_terminal(mouse_x, mouse_y)
          {
            x: mouse_x + 1,
            y: mouse_y + 1,
          }
        end

        # Convert terminal coordinates (1-based) to mouse coordinates (0-based)
        def terminal_to_mouse(terminal_x, terminal_y)
          {
            x: [terminal_x - 1, 0].max,
            y: [terminal_y - 1, 0].max,
          }
        end

        # Normalize selection range ensuring start <= end
        def normalize_selection_range(selection_range)
          return nil unless selection_range&.dig(:start) && selection_range[:end]

          start_pos = selection_range[:start]
          end_pos = selection_range[:end]

          # Swap if end comes before start
          if end_pos[:y] < start_pos[:y] ||
             (end_pos[:y] == start_pos[:y] && end_pos[:x] < start_pos[:x])
            start_pos, end_pos = end_pos, start_pos
          end

          { start: start_pos, end: end_pos }
        end

        # Validate coordinate bounds
        def validate_coordinates(x, y, max_x, max_y)
          x.between?(1, max_x) && y >= 1 && y <= max_y
        end

        # Calculate distance between two points
        def calculate_distance(x1, y1, x2, y2)
          Math.sqrt(((x2 - x1)**2) + ((y2 - y1)**2))
        end

        # Calculate optimal popup position near selection end
        def calculate_popup_position(selection_end, popup_width, popup_height)
          terminal_height, terminal_width = Terminal.size

          # Start with position below selection end
          popup_x = selection_end[:x]
          popup_y = selection_end[:y] + 1

          # Adjust if popup would go off right edge
          popup_x = [terminal_width - popup_width, 1].max if popup_x + popup_width > terminal_width

          # Adjust if popup would go off bottom edge
          if popup_y + popup_height > terminal_height
            # Try to position above selection instead
            popup_y = [selection_end[:y] - popup_height, 1].max
          end

          {
            x: popup_x,
            y: popup_y,
          }
        end

        # Check if coordinates are within bounds
        def within_bounds?(x, y, bounds)
          x >= bounds.x && x < (bounds.x + bounds.width) &&
            y >= bounds.y && y < (bounds.y + bounds.height)
        end

        # Convert line-relative coordinates to absolute terminal coordinates
        def line_to_terminal(line_col, line_start_col, terminal_row)
          {
            x: line_start_col + line_col,
            y: terminal_row,
          }
        end

        # Normalize position hash to consistent format
        def normalize_position(pos)
          return nil unless pos

          {
            x: pos[:x] || pos['x'],
            y: pos[:y] || pos['y'],
          }
        end

        protected

        def required_dependencies
          [] # No dependencies required for coordinate operations
        end
      end
    end
  end
end
