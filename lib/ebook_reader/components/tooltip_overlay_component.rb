# frozen_string_literal: true

require_relative 'base_component'
require_relative '../models/selection_anchor'
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
        render_annotations_overlay(surface, bounds)
        render_annotation_editor_overlay(surface, bounds)
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

      def render_annotations_overlay(surface, bounds)
        overlay = @controller.state.get(%i[reader annotations_overlay])
        return unless overlay.respond_to?(:visible?) && overlay.visible?

        overlay.render(surface, bounds)
      end

      def render_annotation_editor_overlay(surface, bounds)
        overlay = @controller.state.get(%i[reader annotation_editor_overlay])
        return unless overlay.respond_to?(:visible?) && overlay.visible?

        overlay.render(surface, bounds)
      end

      def render_text_highlight(surface, bounds, range, color)
        rendered_lines = @controller.state.get(%i[reader rendered_lines]) || {}
        return if rendered_lines.empty?

        normalized_range = @coordinate_service.normalize_selection_range(range, rendered_lines)
        return unless normalized_range

        start_anchor = EbookReader::Models::SelectionAnchor.from(normalized_range[:start])
        end_anchor = EbookReader::Models::SelectionAnchor.from(normalized_range[:end])
        return unless start_anchor && end_anchor

        geometry_index = build_geometry_index(rendered_lines)
        return if geometry_index.empty?

        ordered = order_geometry(geometry_index.values)
        start_idx = ordered.index { |geo| geo.key == start_anchor.geometry_key }
        end_idx = ordered.index { |geo| geo.key == end_anchor.geometry_key }
        return unless start_idx && end_idx

        ordered[start_idx..end_idx].each do |geometry|
          start_cell = geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
          end_cell = geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length
          render_geometry_highlight(surface, bounds, geometry, start_cell, end_cell, color)
        end
      end

      def render_geometry_highlight(surface, bounds, geometry, start_cell, end_cell, color)
        return if end_cell <= start_cell

        start_char = char_index_for_cell(geometry, start_cell)
        end_char = char_index_for_cell(geometry, end_cell)
        return if end_char <= start_char

        segment_text = geometry.plain_text[start_char...end_char]
        return if segment_text.nil? || segment_text.empty?

        highlight = "#{color}#{COLOR_TEXT_PRIMARY}#{segment_text}#{Terminal::ANSI::RESET}"
        start_col = screen_column_for_cell(geometry, start_cell)
        surface.write(bounds, geometry.row, start_col, highlight)
        record_selection_segment(geometry.row, start_col, segment_text)
      end

      def screen_column_for_cell(geometry, cell_index)
        if cell_index <= 0
          geometry.column_origin
        elsif cell_index >= geometry.cells.length
          geometry.column_origin + geometry.visible_width
        else
          geometry.column_origin + geometry.cells[cell_index].screen_x
        end
      end

      def char_index_for_cell(geometry, cell_index)
        cells = geometry.cells
        return 0 if cells.empty?

        if cell_index <= 0
          0
        elsif cell_index >= cells.length
          geometry.plain_text.length
        else
          cells[cell_index].char_start
        end
      end

      def build_geometry_index(rendered_lines)
        rendered_lines.each_with_object({}) do |(key, info), acc|
          geometry = info[:geometry]
          next unless geometry

          acc[key] = geometry
        end
      end

      def order_geometry(geometries)
        geometries.sort_by do |geo|
          [geo.page_id || 0, geo.line_offset || 0, geo.column_id || 0, geo.row || 0, geo.column_origin || 0]
        end
      end

      def record_selection_segment(row, col, text)
        @last_selection_segments << {
          row: row,
          col: col,
          text: text,
        }
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
