# frozen_string_literal: true

module EbookReader
  module Annotations
    # Handles mouse events for text selection in the reader
    class MouseHandler
      attr_reader :selection_start, :selection_end, :selecting

      def initialize
        reset
      end

      # Parse ANSI mouse event
      def parse_mouse_event(input)
        return nil unless input =~ /\e\[<(\d+);(\d+);(\d+)([Mm])/

        {
          button: ::Regexp.last_match(1).to_i,
          x: ::Regexp.last_match(2).to_i - 1, # Convert to 0-based
          y: ::Regexp.last_match(3).to_i - 1,
          released: ::Regexp.last_match(4) == 'm',
        }
      end

      # Handle mouse event and update selection state
      def handle_event(event)
        return nil unless event

        btn = event[:button]
        rel = event[:released]
        col = event[:x]
        row = event[:y]

        if btn.zero? && !rel # Left button pressed
          start_selection(col, row)
        elsif btn == 32 && @selecting # Mouse dragged
          update_selection(col, row)
        elsif rel && @selecting # Button released
          finish_selection
        end
      end

      # Get normalized selection range
      def selection_range
        return nil unless @selection_start && @selection_end

        start_pos = @selection_start
        end_pos = @selection_end

        # Ensure start comes before end
        sy = start_pos[:y]
        ey = end_pos[:y]
        start_pos, end_pos = end_pos, start_pos if sy > ey || (sy == ey && start_pos[:x] > end_pos[:x])

        { start: start_pos, end: end_pos }
      end

      def reset
        @selecting = false
        @selection_start = nil
        @selection_end = nil
      end

      private

      def start_selection(col, row)
        @selecting = true
        @selection_start = { x: col, y: row }
        @selection_end = { x: col, y: row }
        { type: :selection_start }
      end

      def update_selection(col, row)
        @selection_end = { x: col, y: row }
        { type: :selection_drag }
      end

      def finish_selection
        @selecting = false
        { type: :selection_end }
      end
    end
  end
end
