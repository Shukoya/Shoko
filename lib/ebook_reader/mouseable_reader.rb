# frozen_string_literal: true

require 'ostruct'

require_relative 'reader_controller'
require_relative 'annotations/mouse_handler'
# Removed unused: ui/components/popup_menu
require_relative 'components/enhanced_popup_menu'
require_relative 'components/tooltip_overlay_component'

module EbookReader
  # A Reader that supports mouse interactions for annotations.
  class MouseableReader < ReaderController
    def initialize(epub_path, config = nil, dependencies = nil)
      # Pass dependencies to parent ReaderController
      super

      # Resolve coordinate service (clipboard already resolved in parent)
      @coordinate_service = dependencies.resolve(:coordinate_service)

      @mouse_handler = Annotations::MouseHandler.new
      state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
      @selected_text = nil
      state.dispatch(Domain::Actions::ClearSelectionAction.new)
      state.dispatch(Domain::Actions::ClearRenderedLinesAction.new)
      refresh_annotations
    end

    def run
      terminal_service.enable_mouse
      super
    ensure
      terminal_service.disable_mouse
    end

    def read_input_keys(timeout: nil)
      key = terminal_service.read_input_with_mouse(timeout: timeout)
      return [] unless key

      if key.start_with?("\e[<")
        handle_mouse_input(key)
        return []
      end

      keys = [key]
      while (extra = terminal_service.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event

      editor_overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
      if editor_overlay.respond_to?(:visible?) && editor_overlay.visible? && event[:released]
        handle_annotation_editor_click(event)
        return
      end

      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(state)
      if popup_menu&.visible && event[:released]
        handle_popup_click(event)
        return
      end

      result = @mouse_handler.handle_event(event)
      return unless result

      case result[:type]
      when :selection_drag
        # Keep selection in state while dragging so overlay can render purely from state
        update_state_selection(@mouse_handler.selection_range)
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

      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(state)
      item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

      if item
        handle_popup_action(item)
      else
        state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
        @mouse_handler.reset
        state.dispatch(Domain::Actions::ClearSelectionAction.new)
      end
      draw_screen
    end

    def handle_annotation_editor_click(event)
      coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
      overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
      return unless overlay

      result = overlay.handle_click(coords[:x], coords[:y])
      if result
        ui = dependencies.resolve(:ui_controller)
        if ui.respond_to?(:handle_annotation_editor_overlay_event, true)
          ui.send(:handle_annotation_editor_overlay_event, result)
        end
      end
      @mouse_handler.reset
    ensure
      draw_screen
    end

    def handle_selection_end
      update_state_selection(@mouse_handler.selection_range)
      sel = state.get(%i[reader selection])
      return unless sel

      @selected_text = extract_selected_text(sel)

      if @selected_text && !@selected_text.strip.empty?
        show_popup_menu
      else
        @mouse_handler.reset
        state.dispatch(Domain::Actions::ClearSelectionAction.new)
      end
    end

    def show_popup_menu
      selection = EbookReader::Domain::Selectors::ReaderSelectors.selection(state)
      return unless selection

      # Use enhanced popup menu with coordinate service
      rendered = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(state)
      popup_menu = Components::EnhancedPopupMenu.new(selection, nil, @coordinate_service,
                                                     clipboard_service, rendered)
      state.dispatch(Domain::Actions::UpdatePopupMenuAction.new(popup_menu))
      return unless popup_menu&.visible # Only proceed if menu was created successfully

      # Ensure popup menu has proper focus and state
      switch_mode(:popup_menu)

      # Force a complete redraw to ensure popup appears correctly
      draw_screen
    end

    # Clear any active text selection and hide popup
    def clear_selection!
      state.dispatch(Domain::Actions::ClearPopupMenuAction.new)
      @mouse_handler&.reset
      state&.dispatch(Domain::Actions::ClearSelectionAction.new)
    end

    # Old highlighting methods removed - now handled by TooltipOverlayComponent
    # This eliminates the direct terminal writes that bypassed the component system

    def refresh_annotations
      begin
        service = dependencies.resolve(:annotation_service)
        annotations = service.list_for_book(path)
      rescue StandardError
        annotations = []
      end
      state.dispatch(Domain::Actions::UpdateAnnotationsAction.new(annotations))
    end

    def extract_selected_text(range)
      selection_service = dependencies.resolve(:selection_service)
      if selection_service.respond_to?(:extract_from_state)
        selection_service.extract_from_state(state, range)
      else
        rendered = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(state)
        selection_service.extract_text(range, rendered)
      end
    end

    def update_state_selection(mouse_range)
      anchor_range = anchor_range_from_mouse(mouse_range)
      if anchor_range
        state.dispatch(Domain::Actions::UpdateSelectionAction.new(anchor_range))
      else
        state.dispatch(Domain::Actions::ClearSelectionAction.new)
      end
    end

    def anchor_range_from_mouse(mouse_range)
      return nil unless mouse_range

      rendered = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(state)
      return nil if rendered.empty?

      start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
      end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
      return nil unless start_anchor && end_anchor

      @coordinate_service.normalize_selection_range(
        { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
      )
    end

    def copy_to_clipboard(text)
      ui = dependencies.resolve(:ui_controller)
      clipboard_service.copy_with_feedback(text) do |message|
        ui.set_message(message)
      rescue StandardError
        # best-effort
      end
    rescue Domain::Services::ClipboardService::ClipboardError => e
      begin
        ui.set_message("Copy failed: #{e.message}")
      rescue StandardError
        # ignore
      end
      false
    end

    # Column helpers moved to CoordinateService
  end
end
