# frozen_string_literal: true

module EbookReader
  # Extension to add mouse support to Reader
  module ReaderMouseExtension
    def self.included(base)
      base.class_eval do
        alias_method :initialize_without_mouse, :initialize
        alias_method :initialize, :initialize_with_mouse
        
        alias_method :draw_screen_without_mouse, :draw_screen
        alias_method :draw_screen, :draw_screen_with_mouse
      end
    end

    def initialize_with_mouse(*args)
      initialize_without_mouse(*args)
      @mouse_handler = Annotations::MouseHandler.new
      @popup_menu = nil
      @selected_text = nil
      @selection_range = nil
    end

    def draw_screen_with_mouse
      draw_screen_without_mouse
      
      # Highlight selected text if any
      if @mouse_handler.selecting || @selection_range
        highlight_selection
      end
      
      # Draw popup menu if visible
      @popup_menu&.render
      
      Terminal.end_frame
    end

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event
      
      # Handle popup menu clicks first
      if @popup_menu&.visible && event[:released]
        item = @popup_menu.handle_click(event[:x], event[:y])
        
        if item
          handle_popup_action(item)
        else
          # Click outside menu - close it
          @popup_menu = nil
          @mouse_handler.reset
          @selection_range = nil
        end
        return
      end
      
      # Handle text selection
      result = @mouse_handler.handle_event(event)
      
      case result&.fetch(:type, nil)
      when :selection_end
        handle_selection_end
      end
    end

    private

    def handle_selection_end
      @selection_range = @mouse_handler.selection_range
      return unless @selection_range
      
      @selected_text = extract_selected_text(@selection_range)
      
      if @selected_text && !@selected_text.strip.empty?
        show_popup_menu
      else
        @mouse_handler.reset
        @selection_range = nil
      end
    end

    def show_popup_menu
      return unless @selection_range
      
      # Position menu below selected text
      end_pos = @selection_range[:end]
      menu_x = [end_pos[:x], Terminal.size[1] - 25].min
      menu_y = [end_pos[:y] + 1, Terminal.size[0] - 5].min
      
      @popup_menu = UI::Components::PopupMenu.new(
        menu_x, menu_y, 
        ['Create Annotation', 'Copy to Clipboard']
      )
    end

    def handle_popup_action(action)
      case action
      when 'Create Annotation'
        switch_mode(:annotation_editor, 
          text: @selected_text, 
          range: @selection_range,
          chapter_index: @current_chapter
        )
      when 'Copy to Clipboard'
        copy_to_clipboard(@selected_text)
        set_message('Copied to clipboard!')
      end
      
      @popup_menu = nil
      @mouse_handler.reset
      @selection_range = nil
    end

    def highlight_selection
      range = @mouse_handler.selection_range || @selection_range
      return unless range
      
      # Calculate actual screen positions based on current view
      # This is simplified - you'll need to adjust based on your rendering
      start_pos = range[:start]
      end_pos = range[:end]
      
      # Apply highlight color to selected range
      if start_pos[:y] == end_pos[:y]
        # Single line selection
        (start_pos[:x]..end_pos[:x]).each do |x|
          # Rewrite character at position with highlight
          Terminal.write_differential(start_pos[:y], x, 
            "#{Terminal::ANSI::BG_BRIGHT_GREEN}#{Terminal::ANSI::BLACK} #{Terminal::ANSI::RESET}")
        end
      else
        # Multi-line selection - implement as needed
      end
    end

    def extract_selected_text(range)
      # Extract text based on selection range
      # This needs to map screen coordinates to actual text
      # Implementation depends on your current rendering logic
      
      # For now, return placeholder
      "Selected text from (#{range[:start][:x]},#{range[:start][:y]}) to (#{range[:end][:x]},#{range[:end][:y]})"
    end

    def copy_to_clipboard(text)
      cmd = case RUBY_PLATFORM
      when /darwin/ then "pbcopy"
      when /linux/
        if system("which wl-copy > /dev/null 2>&1") 
          "wl-copy"
        elsif system("which xclip > /dev/null 2>&1")
          "xclip -selection clipboard"
        end
      end
      
      if cmd
        IO.popen(cmd, 'w') { |io| io.write(text) }
      end
    rescue StandardError
      nil
    end
  end
end
