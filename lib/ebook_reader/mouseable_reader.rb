# frozen_string_literal: true

require 'ostruct'

require_relative 'reader_controller'
require_relative 'annotations/mouse_handler'
require_relative 'annotations/annotation_store'
# Removed unused: ui/components/popup_menu
require_relative 'components/enhanced_popup_menu'
require_relative 'components/tooltip_overlay_component'
require_relative 'reader_modes/annotation_editor_mode'
require_relative 'reader_modes/annotations_mode'
require_relative 'terminal_mouse_patch'

module EbookReader
  # A Reader that supports mouse interactions for annotations.
  class MouseableReader < ReaderController
    def initialize(epub_path, config = nil, dependencies = nil)
      # Pass dependencies to parent ReaderController
      super

      # Resolve coordinate service (clipboard already resolved in parent)
      @coordinate_service = @dependencies.resolve(:coordinate_service)
      @terminal_service = @dependencies.resolve(:terminal_service)

      @mouse_handler = Annotations::MouseHandler.new
      @state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
      @selected_text = nil
      @state.dispatch(Domain::Actions::ClearSelectionAction.new)
      @state.dispatch(Domain::Actions::ClearRenderedLinesAction.new)
      @tooltip_overlay = Components::TooltipOverlayComponent.new(self)
      refresh_annotations
    end

    def run
      @terminal_service.enable_mouse
      super
    ensure
      @terminal_service.disable_mouse
    end

    def draw_screen
      # Render the base UI via components
      rendered_lines = @state.get([:reader, :rendered_lines])
      rendered_lines.clear
      @state.dispatch(Domain::Actions::UpdateRenderedLinesAction.new(rendered_lines))
      super

      # Use consolidated tooltip overlay component for all highlighting
      if %i[read popup_menu].include?(@state.get([:reader, :mode]))
        height, width = @terminal_service.size
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface = @terminal_service.create_surface
        @tooltip_overlay.render(surface, bounds)
      end

      @terminal_service.end_frame
    end

    def read_input_keys
      key = @terminal_service.read_input_with_mouse
      return [] unless key

      if key.start_with?("\e[<")
        handle_mouse_input(key)
        return []
      end

      keys = [key]
      while (extra = @terminal_service.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event

      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
      if popup_menu&.visible && event[:released]
        handle_popup_click(event)
        return
      end

      result = @mouse_handler.handle_event(event)
      return unless result

      case result[:type]
      when :selection_drag
        refresh_highlighting
      when :selection_end
        handle_selection_end
        draw_screen
      else
        draw_screen
      end
    end

    private

    def handle_popup_click(event)
      # Use coordinate service for consistent mouse-to-terminal conversion
      terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])

      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
      item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

      if item
        handle_popup_action(item)
      else
        @state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
        @mouse_handler.reset
        @state.dispatch(Domain::Actions::ClearSelectionAction.new)
      end
      draw_screen
    end

    def refresh_highlighting
      @terminal_service.size
      # Re-render content area only
      super
      # Use consolidated tooltip overlay for all highlighting
      height, width = @terminal_service.size
      bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      surface = @terminal_service.create_surface
      @tooltip_overlay.render(surface, bounds)
      @terminal_service.end_frame
    end

    def handle_selection_end
      @state.dispatch(Domain::Actions::UpdateSelectionAction.new(@mouse_handler.selection_range))
      return unless @state.get([:reader, :selection])

      @selected_text = extract_selected_text(@state.get([:reader, :selection]))

      if @selected_text && !@selected_text.strip.empty?
        show_popup_menu
      else
        @mouse_handler.reset
        @state.dispatch(Domain::Actions::ClearSelectionAction.new)
      end
    end

    def show_popup_menu
      selection = EbookReader::Domain::Selectors::ReaderSelectors.selection(@state)
      return unless selection

      # Use enhanced popup menu with coordinate service
      popup_menu = Components::EnhancedPopupMenu.new(selection, nil, @coordinate_service)
      @state.dispatch(Domain::Actions::UpdatePopupMenuAction.new(popup_menu))
      return unless popup_menu&.visible # Only proceed if menu was created successfully

      # Ensure popup menu has proper focus and state
      switch_mode(:popup_menu)

      # Force a complete redraw to ensure popup appears correctly
      draw_screen
    end

    # Clear any active text selection and hide popup
    def clear_selection!
      @state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
      @mouse_handler&.reset
      @state.dispatch(Domain::Actions::ClearSelectionAction.new) if @state
    end

    # Old highlighting methods removed - now handled by TooltipOverlayComponent
    # This eliminates the direct terminal writes that bypassed the component system

    def refresh_annotations
      annotations = Annotations::AnnotationStore.get(@path)
      @state.dispatch(Domain::Actions::UpdateAnnotationsAction.new(annotations))
    end

    def extract_selected_text(range)
      return '' unless range && @state.get([:reader, :rendered_lines])
      selection_service = @dependencies.resolve(:selection_service)
      selection_service.extract_text(range, @state.get([:reader, :rendered_lines]))
    end

    def copy_to_clipboard(text)
      @clipboard_service.copy_with_feedback(text) do |message|
        set_message(message)
      end
    rescue Domain::Services::ClipboardService::ClipboardError => e
      set_message("Copy failed: #{e.message}")
      false
    end

    def determine_column_bounds(click_pos)
      # Find which column the click position belongs to
      terminal_coords = @coordinate_service.mouse_to_terminal(0, click_pos[:y])
      terminal_row = terminal_coords[:y]

      @state.get([:reader, :rendered_lines]).each_value do |line_info|
        next unless line_info[:row] == terminal_row

        line_start_col = line_info[:col]
        line_end_col = line_info[:col_end] || (line_start_col + line_info[:width] - 1)

        if click_pos[:x].between?(line_start_col, line_end_col)
          return { start: line_start_col, end: line_end_col }
        end
      end

      nil
    end

    def column_overlaps?(line_start, line_end, target_bounds)
      # Check if line segment overlaps with target column bounds
      !(line_end < target_bounds[:start] || line_start > target_bounds[:end])
    end
  end
end
