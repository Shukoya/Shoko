# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'annotations/mouse_handler'
require_relative 'annotations/annotation_store'
require_relative 'ui/components/popup_menu'
require_relative 'components/enhanced_popup_menu'
require_relative 'components/tooltip_overlay_component'
require_relative 'reader_modes/annotation_editor_mode'
require_relative 'reader_modes/annotations_mode'
require_relative 'terminal_mouse_patch'
require_relative 'services/coordinate_service'
require_relative 'services/clipboard_service'

module EbookReader
  # A Reader that supports mouse interactions for annotations.
  class MouseableReader < ReaderController
    def initialize(epub_path, config = Config.new)
      super
      @mouse_handler = Annotations::MouseHandler.new
      @state.popup_menu = nil
      @selected_text = nil
      @state.selection = nil
      @state.rendered_lines = {}
      @tooltip_overlay = Components::TooltipOverlayComponent.new(self)
      refresh_annotations
    end

    def run
      Terminal.enable_mouse
      super
    ensure
      Terminal.disable_mouse
    end

    def draw_screen
      # Render the base UI via components
      @state.rendered_lines.clear
      super

      # Use consolidated tooltip overlay component for all highlighting
      if %i[read popup_menu].include?(@state.mode)
        height, width = Terminal.size
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface = Components::Surface.new(Terminal)
        @tooltip_overlay.render(surface, bounds)
      end

      Terminal.end_frame
    end

    def read_input_keys
      key = Terminal.read_input_with_mouse
      return [] unless key

      if key.start_with?("\e[<")
        handle_mouse_input(key)
        return []
      end

      keys = [key]
      while (extra = Terminal.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event

      if @state.popup_menu&.visible && event[:released]
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
      terminal_coords = Services::CoordinateService.mouse_to_terminal(event[:x], event[:y])

      item = @state.popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

      if item
        handle_popup_action(item)
      else
        @state.popup_menu = nil
        @mouse_handler.reset
        @state.selection = nil
      end
      draw_screen
    end

    def refresh_highlighting
      Terminal.size
      # Re-render content area only
      super
      # Use consolidated tooltip overlay for all highlighting
      height, width = Terminal.size
      bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      surface = Components::Surface.new(Terminal)
      @tooltip_overlay.render(surface, bounds)
      Terminal.end_frame
    end

    def handle_selection_end
      @state.selection = @mouse_handler.selection_range
      return unless @state.selection

      @selected_text = extract_selected_text(@state.selection)

      if @selected_text && !@selected_text.strip.empty?
        show_popup_menu
      else
        @mouse_handler.reset
        @state.selection = nil
      end
    end

    def show_popup_menu
      return unless @state.selection

      # Use enhanced popup menu with coordinate service
      @state.popup_menu = Components::EnhancedPopupMenu.new(@state.selection)
      return unless @state.popup_menu&.visible # Only proceed if menu was created successfully

      # Ensure popup menu has proper focus and state
      switch_mode(:popup_menu)
      
      # Force a complete redraw to ensure popup appears correctly
      draw_screen
    end

    # Clear any active text selection and hide popup
    def clear_selection!
      @state.popup_menu = nil
      @mouse_handler&.reset
      @state.selection = nil if @state
    end

    # Old highlighting methods removed - now handled by TooltipOverlayComponent
    # This eliminates the direct terminal writes that bypassed the component system

    def refresh_annotations
      @state.annotations = Annotations::AnnotationStore.get(@path)
    end

    def extract_selected_text(range)
      return '' unless range && @state.rendered_lines

      # Use coordinate service for consistent normalization
      normalized_range = Services::CoordinateService.normalize_selection_range(range)
      return '' unless normalized_range

      start_pos = normalized_range[:start]
      end_pos = normalized_range[:end]
      text = []

      (start_pos[:y]..end_pos[:y]).each do |y|
        # Use coordinate service for terminal coordinate conversion
        terminal_coords = Services::CoordinateService.mouse_to_terminal(0, y)
        terminal_row = terminal_coords[:y]

        line_info = @state.rendered_lines[terminal_row]
        next unless line_info

        line_text = line_info[:text]
        line_start_col = line_info[:col]

        start_char_index = (y == start_pos[:y] ? start_pos[:x] - line_start_col : 0).clamp(0,
                                                                                           line_text.length - 1)
        end_char_index = (y == end_pos[:y] ? end_pos[:x] - line_start_col : line_text.length - 1).clamp(
          0, line_text.length - 1
        )

        text << line_text[start_char_index..end_char_index] if end_char_index >= start_char_index
      end

      text.join("\n")
    end

    def copy_to_clipboard(text)
      Services::ClipboardService.copy_with_feedback(text) do |message|
        set_message(message)
      end
    rescue Services::ClipboardService::ClipboardError => e
      set_message("Copy failed: #{e.message}")
      false
    end
  end
end
