# frozen_string_literal: true

module EbookReader
  module Services
    # Centralized coordinate system management to eliminate the chaos
    # of 0-based vs 1-based coordinate conversions throughout the codebase.
    #
    # This service provides a single source of truth for coordinate transformations
    # and ensures consistency across mouse events, terminal rendering, and text selection.
    class CoordinateService
      # Convert mouse coordinates (0-based) to terminal coordinates (1-based)
      # @param mouse_x [Integer] 0-based mouse X coordinate
      # @param mouse_y [Integer] 0-based mouse Y coordinate
      # @return [Hash] {:x, :y} in terminal coordinates (1-based)
      def self.mouse_to_terminal(mouse_x, mouse_y)
        {
          x: mouse_x + 1,
          y: mouse_y + 1,
        }
      end

      # Convert terminal coordinates (1-based) to mouse coordinates (0-based)
      # @param terminal_x [Integer] 1-based terminal X coordinate
      # @param terminal_y [Integer] 1-based terminal Y coordinate
      # @return [Hash] {:x, :y} in mouse coordinates (0-based)
      def self.terminal_to_mouse(terminal_x, terminal_y)
        {
          x: [terminal_x - 1, 0].max,
          y: [terminal_y - 1, 0].max,
        }
      end

      # Normalize selection range to ensure consistent coordinate format
      # @param range [Hash] Selection range with :start and :end positions
      # @return [Hash] Normalized range with consistent coordinate format
      def self.normalize_selection_range(range)
        return nil unless range

        start_pos = normalize_position(range[:start] || range['start'])
        end_pos = normalize_position(range[:end] || range['end'])

        return nil unless start_pos && end_pos

        # Ensure start comes before end
        if start_pos[:y] > end_pos[:y] ||
           (start_pos[:y] == end_pos[:y] && start_pos[:x] > end_pos[:x])
          start_pos, end_pos = end_pos, start_pos
        end

        { start: start_pos, end: end_pos }
      end

      # Calculate optimal popup position near selection end
      # @param selection_end [Hash] End position of selection {:x, :y}
      # @param popup_width [Integer] Width of popup in characters
      # @param popup_height [Integer] Height of popup in lines
      # @return [Hash] Optimal popup position {:x, :y} in terminal coordinates
      def self.calculate_popup_position(selection_end, popup_width, popup_height)
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

      # Convert line-relative coordinates to absolute terminal coordinates
      # @param line_col [Integer] Column within the line
      # @param line_start_col [Integer] Where the line starts on terminal
      # @param terminal_row [Integer] Which terminal row (1-based)
      # @return [Hash] Absolute terminal coordinates {:x, :y}
      def self.line_to_terminal(line_col, line_start_col, terminal_row)
        {
          x: line_start_col + line_col,
          y: terminal_row,
        }
      end

      # Check if coordinates are within bounds
      # @param x [Integer] X coordinate
      # @param y [Integer] Y coordinate
      # @param bounds [Components::Rect] Bounds to check against
      # @return [Boolean] True if coordinates are within bounds
      def self.within_bounds?(x, y, bounds)
        x >= bounds.x && x < (bounds.x + bounds.width) &&
          y >= bounds.y && y < (bounds.y + bounds.height)
      end

      # Normalize position hash to consistent format
      # @param pos [Hash] Position with either symbol or string keys
      # @return [Hash] Normalized position with symbol keys
      def self.normalize_position(pos)
        return nil unless pos

        {
          x: pos[:x] || pos['x'],
          y: pos[:y] || pos['y'],
        }
      end
    end
  end
end
