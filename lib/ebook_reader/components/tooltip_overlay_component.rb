# frozen_string_literal: true

require_relative 'base_component'
module EbookReader
  module Components
    # Unified overlay component that handles all tooltip/popup rendering
    # including text selection highlighting, popup menus, and annotations.
    #
    # This component consolidates the scattered rendering logic and provides
    # consistent coordinate handling for the fragile tooltip system.
    class TooltipOverlayComponent < BaseComponent
      include Constants::UIConstants

      def initialize(controller, coordinate_service:)
        @controller = controller
        @coordinate_service = coordinate_service
        @last_selection_segments = []
      end

      # Render all overlay elements: highlights, popups, tooltips
      def do_render(surface, bounds)
        # Render in specific order to ensure proper layering
        clear_previous_selection_artifacts(surface, bounds)
        render_saved_annotations(surface, bounds)
        render_active_selection(surface, bounds)
        render_popup_menu(surface, bounds)
      end

      private

      def render_saved_annotations(surface, bounds)
        state = @controller.state
        anns = state.get(%i[reader annotations])
        return unless anns

        current_ch = state.get(%i[reader current_chapter])
        anns
                   .select do |a|
          a['chapter_index'] == current_ch
        end
                   .each do |annotation|
          render_text_highlight(surface, bounds, annotation['range'], HIGHLIGHT_BG_SAVED)
        end
      end

      def render_active_selection(surface, bounds)
        # Render current selection highlight
        selection_range = @controller.state.get(%i[reader selection])

        unless selection_range
          # No active selection; keep any previously rendered segments for one clear pass
          @pending_clear = true if @last_selection_segments.any?
          return
        end

        # Reset tracking for this frame
        @last_selection_segments.clear
        render_text_highlight(surface, bounds, selection_range, HIGHLIGHT_BG_ACTIVE)
      end

      def render_popup_menu(surface, bounds)
        popup_menu = @controller.state.get(%i[reader popup_menu])
        return unless popup_menu&.visible

        # Unified component rendering path
        popup_menu.render(surface, bounds)
      end

      def render_text_highlight(surface, bounds, range, color)
        normalized_range = @coordinate_service.normalize_selection_range(range)
        return unless normalized_range

        rendered_lines = @controller.state.get(%i[reader rendered_lines]) || {}
        start_pos = normalized_range[:start]
        end_pos = normalized_range[:end]
        start_y = start_pos[:y]
        end_y = end_pos[:y]

        # Determine which column the selection started in (for column-aware highlighting)
        target_column_bounds = @coordinate_service.column_bounds_for(start_pos, rendered_lines)

        (start_y..end_y).each do |y|
          render_highlighted_line(surface, bounds, rendered_lines, y, start_pos, end_pos, color,
                                  target_column_bounds)
        end
      end

      def render_highlighted_line(surface, bounds, rendered_lines, y, start_pos, end_pos, color,
                                  target_column_bounds = nil)
        # Convert 0-based selection coordinates to 1-based terminal row
        terminal_row = y + 1
        start_y = start_pos[:y]
        end_y = end_pos[:y]
        start_x = start_pos[:x]
        end_x = end_pos[:x]
        is_start_row = (y == start_y)
        is_end_row = (y == end_y)

        # Find line segments for this row that belong to the target column
        rendered_lines.each_value do |line_info|
          next unless line_info[:row] == terminal_row

          line_start_col = line_info[:col]
          line_end_col = line_info[:col_end] || (line_start_col + line_info[:width] - 1)

          # If we have column bounds, only highlight within the target column
          if target_column_bounds
            overlaps = @coordinate_service.column_overlaps?(line_start_col, line_end_col, target_column_bounds)
            next unless overlaps

            # Constrain selection to target column bounds
            row_start_x = is_start_row ? start_x : target_column_bounds[:start]
            row_end_x = is_end_row ? end_x : target_column_bounds[:end]
          else
            # Original behavior for single-column mode or saved annotations
            row_start_x = is_start_row ? start_x : 0
            row_end_x = is_end_row ? end_x : Float::INFINITY
          end

          # Skip if selection doesn't overlap with this line segment
          next if row_end_x < line_start_col || row_start_x > line_end_col

          # Render highlight for this line segment
          render_line_segment_highlight(surface, bounds, line_info, y, start_pos, end_pos, color)
        end
      end

      def render_line_segment_highlight(surface, bounds, line_info, y, start_pos, end_pos, color)
        line_text = line_info[:text]
        return if line_text.empty?

        line_start_col = line_info[:col]
        terminal_row = line_info[:row]

        # Calculate highlight boundaries within this line segment
        highlight_bounds = calculate_line_highlight_bounds(
          line_text, line_start_col, y, start_pos, end_pos
        )
        return unless highlight_bounds

        # Build highlighted line text (overlay approach - don't modify original)
        highlighted_text = build_highlighted_text(
          line_text, highlight_bounds, color
        )

        # Render the highlighted line using surface
        surface.write(bounds, terminal_row, line_start_col, highlighted_text)

        # Track segments for cleanup when selection disappears
        b_start = highlight_bounds[:start]
        b_end = highlight_bounds[:end]
        seg_start = line_start_col + b_start
        seg_len = b_end - b_start + 1
        original_text = line_text[b_start..b_end]
        @last_selection_segments << { row: terminal_row, col: seg_start, len: seg_len,
                                      text: original_text }
      end

      def calculate_line_highlight_bounds(line_text, line_start_col, current_y, start_pos, end_pos)
        max_index = line_text.length - 1
        return nil if max_index.negative?

        # Calculate start and end indices within this line
        start_idx_raw = (current_y == start_pos[:y] ? start_pos[:x] - line_start_col : 0)
        end_idx_raw = (current_y == end_pos[:y] ? end_pos[:x] - line_start_col : max_index)

        # Clamp to valid boundaries
        start_idx = start_idx_raw.clamp(0, max_index)
        end_idx = end_idx_raw.clamp(0, max_index)

        return nil if end_idx < start_idx

        { start: start_idx, end: end_idx }
      end

      def build_highlighted_text(line_text, bounds, color)
        result = ''
        reset = Terminal::ANSI::RESET

        # Add text before highlight
        s = bounds[:start]
        e = bounds[:end]
        result += line_text[0...s] if s.positive?

        # Add highlighted portion
        highlighted_part = line_text[s..e]
        result += "#{color}#{COLOR_TEXT_PRIMARY}#{highlighted_part}#{reset}"

        # Add text after highlight
        result += line_text[(e + 1)..] if e < line_text.length - 1
        
        result
      end

      # If selection was present on previous frame but not this one, explicitly repaint
      # the previously highlighted character cells to clear any lingering background color
      def clear_previous_selection_artifacts(surface, bounds)
        return unless @pending_clear && @last_selection_segments.any?

        @last_selection_segments.each do |seg|
          safe_text = seg[:text] || ''
          reset = Terminal::ANSI::RESET
          repaint = "#{reset}#{COLOR_TEXT_PRIMARY}#{safe_text}#{reset}"
          surface.write(bounds, seg[:row], seg[:col], repaint)
        end

        @last_selection_segments.clear
        @pending_clear = false
      end

      # Column bounds and overlap checks are now handled by CoordinateService
    end
  end
end
