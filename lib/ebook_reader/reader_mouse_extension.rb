# frozen_string_literal: true

module EbookReader
  # Extension to add mouse support to Reader.
  # Every mouse event triggers an immediate redraw, including while dragging,
  # so selection highlighting and popup menus appear with no delay.
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
      @rendered_lines = {}
      refresh_annotations
    end

    def draw_screen_with_mouse
      @rendered_lines.clear
      draw_screen_without_mouse

      highlight_saved_annotations
      highlight_selection if @mouse_handler.selecting || @selection_range
      @popup_menu&.render

      Terminal.end_frame
    end

    # Process all mouse events and refresh the screen after each one to provide
    # instant visual feedback. This includes intermediate drag events so users
    # see text highlighting as they select.
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
      else
        # Handle text selection
        result = @mouse_handler.handle_event(event)

        handle_selection_end if result&.fetch(:type, nil) == :selection_end
      end

      draw_screen
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
      highlight_range(range, Terminal::ANSI::BG_BRIGHT_GREEN) if range
    end

    def highlight_saved_annotations
      return unless @annotations
      @annotations.select { |a| a['chapter_index'] == @current_chapter }
                  .each do |ann|
        highlight_range(ann['range'], Terminal::ANSI::BG_BRIGHT_YELLOW)
      end
    end

    def highlight_range(range, color)
      return unless range

      start_pos = range[:start] || range['start']
      end_pos = range[:end] || range['end']
      return unless start_pos && end_pos

      (start_pos[:y]..end_pos[:y]).each do |y|
        row = y + 1
        line_info = @rendered_lines[row]
        next unless line_info

        line_text = line_info[:text]
        line_start = line_info[:col]

        start_idx = if y == start_pos[:y]
                      start_pos[:x] + 1 - line_start
                    else
                      0
                    end
        end_idx = if y == end_pos[:y]
                    end_pos[:x] + 1 - line_start
                  else
                    line_text.length - 1
                  end

        start_idx = [[start_idx, line_text.length - 1].min, 0].max
        end_idx = [[end_idx, line_text.length - 1].min, 0].max
        next if end_idx < start_idx

        (start_idx..end_idx).each do |i|
          col = line_start + i
          char = line_text[i] || ' '
          Terminal.write(row, col, "#{color}#{Terminal::ANSI::BLACK}#{char}#{Terminal::ANSI::RESET}")
        end
      end
    end

    def refresh_annotations
      @annotations = Annotations::AnnotationStore.get(@path)
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
