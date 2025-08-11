# frozen_string_literal: true

require_relative 'base_component'
require_relative '../services/coordinate_service'

module EbookReader
  module Components
    # Unified overlay component that handles all tooltip/popup rendering
    # including text selection highlighting, popup menus, and annotations.
    #
    # This component consolidates the scattered rendering logic and provides
    # consistent coordinate handling for the fragile tooltip system.
    class TooltipOverlayComponent < BaseComponent
      def initialize(controller)
        @controller = controller
      end

      # Render all overlay elements: highlights, popups, tooltips
      def render(surface, bounds)
        # Render in specific order to ensure proper layering
        render_saved_annotations(surface, bounds)
        render_active_selection(surface, bounds)
        render_popup_menu(surface, bounds)
      end

      private

      def render_saved_annotations(surface, bounds)
        return unless @controller.state.annotations

        @controller.state.annotations
                   .select { |a| a['chapter_index'] == @controller.state.current_chapter }
                   .each do |annotation|
          render_text_highlight(surface, bounds, annotation['range'], Terminal::ANSI::BG_CYAN)
        end
      end

      def render_active_selection(surface, bounds)
        # Render current selection highlight
        selection_range = @controller.instance_variable_get(:@mouse_handler)&.selection_range ||
                          @controller.state.selection

        return unless selection_range

        render_text_highlight(surface, bounds, selection_range, Terminal::ANSI::BG_BLUE)
      end

      def render_popup_menu(surface, bounds)
        popup_menu = @controller.state.popup_menu
        return unless popup_menu&.visible

        # Handle both old and new popup menu interfaces
        if popup_menu.respond_to?(:render)
          popup_menu.render(surface, bounds)
        elsif popup_menu.respond_to?(:render_with_surface)
          popup_menu.render_with_surface(surface, bounds)
        end
      end

      def render_text_highlight(surface, bounds, range, color)
        normalized_range = Services::CoordinateService.normalize_selection_range(range)
        return unless normalized_range

        rendered_lines = @controller.state.rendered_lines || {}
        start_pos = normalized_range[:start]
        end_pos = normalized_range[:end]

        (start_pos[:y]..end_pos[:y]).each do |y|
          render_highlighted_line(surface, bounds, rendered_lines, y, start_pos, end_pos, color)
        end
      end

      def render_highlighted_line(surface, bounds, rendered_lines, y, start_pos, end_pos, color)
        # Convert 0-based selection coordinates to 1-based terminal row
        terminal_row = y + 1
        line_info = rendered_lines[terminal_row]
        return unless line_info

        line_text = line_info[:text].dup
        return if line_text.empty?

        line_start_col = line_info[:col]

        # Calculate highlight boundaries within this line
        highlight_bounds = calculate_line_highlight_bounds(
          line_text, line_start_col, y, start_pos, end_pos
        )
        return unless highlight_bounds

        # Build highlighted line text
        highlighted_text = build_highlighted_text(
          line_text, highlight_bounds, color
        )

        # Render the highlighted line using surface
        surface.write(bounds, terminal_row, line_start_col, highlighted_text)
      end

      def calculate_line_highlight_bounds(line_text, line_start_col, current_y, start_pos, end_pos)
        max_index = line_text.length - 1
        return nil if max_index.negative?

        # Calculate start and end indices within this line
        start_idx_raw = (current_y == start_pos[:y] ? start_pos[:x] - line_start_col : 0)
        end_idx_raw = (current_y == end_pos[:y] ? end_pos[:x] - line_start_col : max_index)

        # Clamp to valid boundaries
        start_idx = [[start_idx_raw, 0].max, max_index].min
        end_idx = [[end_idx_raw, 0].max, max_index].min

        return nil if end_idx < start_idx

        { start: start_idx, end: end_idx }
      end

      def build_highlighted_text(line_text, bounds, color)
        result = ''

        # Add text before highlight
        result += line_text[0...bounds[:start]] if bounds[:start].positive?

        # Add highlighted portion
        highlighted_part = line_text[bounds[:start]..bounds[:end]]
        result += "#{color}#{Terminal::ANSI::WHITE}#{highlighted_part}#{Terminal::ANSI::RESET}"

        # Add text after highlight
        result += line_text[(bounds[:end] + 1)..] if bounds[:end] < line_text.length - 1

        result
      end
    end
  end
end
