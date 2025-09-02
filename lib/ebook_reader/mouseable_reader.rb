# frozen_string_literal: true

require 'ostruct'

require_relative 'reader_controller'
require_relative 'annotations/mouse_handler'
# Removed unused: ui/components/popup_menu
require_relative 'components/enhanced_popup_menu'
require_relative 'components/tooltip_overlay_component'
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
      rendered_lines = @state.get(%i[reader rendered_lines])
      rendered_lines.clear
      @state.dispatch(Domain::Actions::UpdateRenderedLinesAction.new(rendered_lines))
      super

      # Overlay and frame end are handled by ReaderController now
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
        # Keep selection in state while dragging so overlay can render purely from state
        @state.dispatch(Domain::Actions::UpdateSelectionAction.new(@mouse_handler.selection_range))
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
      # Defer to ReaderController draw, which renders overlay and ends frame
      super
    end

    def handle_selection_end
      @state.dispatch(Domain::Actions::UpdateSelectionAction.new(@mouse_handler.selection_range))
      return unless @state.get(%i[reader selection])

      @selected_text = extract_selected_text(@state.get(%i[reader selection]))

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
      popup_menu = Components::EnhancedPopupMenu.new(selection, nil, @coordinate_service,
                                                     @clipboard_service)
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
      @state&.dispatch(Domain::Actions::ClearSelectionAction.new)
    end

    # Old highlighting methods removed - now handled by TooltipOverlayComponent
    # This eliminates the direct terminal writes that bypassed the component system

    def refresh_annotations
      begin
        service = @dependencies.resolve(:annotation_service)
        annotations = service.list_for_book(@path)
      rescue StandardError
        annotations = []
      end
      @state.dispatch(Domain::Actions::UpdateAnnotationsAction.new(annotations))
    end

    def extract_selected_text(range)
      return '' unless range && @state.get(%i[reader rendered_lines])

      selection_service = @dependencies.resolve(:selection_service)
      selection_service.extract_text(range, @state.get(%i[reader rendered_lines]))
    end

    def copy_to_clipboard(text)
      @clipboard_service.copy_with_feedback(text) do |message|
        set_message(message)
      end
    rescue Domain::Services::ClipboardService::ClipboardError => e
      set_message("Copy failed: #{e.message}")
      false
    end

    # Column helpers moved to CoordinateService
  end
end
