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

    def initialize_with_mouse(*)
      initialize_without_mouse(*)
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

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event

      # Handle popup menu clicks first, as they are highest priority
      if @popup_menu&.visible && event[:released]
        handle_popup_click(event)
        return
      end

      # Process text selection events
      result = @mouse_handler.handle_event(event)
      return unless result

      case result[:type]
      when :selection_drag
        # Fast path for dragging: only redraw content and highlights
        refresh_highlighting
      when :selection_end
        # Finalize selection and show popup menu
        handle_selection_end
        draw_screen # Full redraw to show popup
      else
        # For selection_start or other events, a full but quick redraw is fine
        draw_screen
      end
    end

    private

    def handle_popup_click(event)
      item = @popup_menu.handle_click(event[:x], event[:y])

      if item
        handle_popup_action(item)
      else
        # Clicked outside the menu, so close it and reset state
        @popup_menu = nil
        @mouse_handler.reset
        @selection_range = nil
      end
      draw_screen # Redraw to remove the popup
    end

    # A lightweight renderer that only redraws the reading content and highlights.
    # This is called repeatedly during a mouse drag.
    def refresh_highlighting
      height, width = Terminal.size

      # This is the key optimization: we call a content-only renderer
      # instead of the full draw_screen, avoiding header/footer/cache logic.
      draw_reading_content(height, width)

      # Re-apply any saved annotations and the current selection highlight
      highlight_saved_annotations
      highlight_selection

      # Ensure the terminal updates visually
      Terminal.end_frame
    end

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
      menu_items = ['Create Annotation', 'Copy to Clipboard']
      menu_width = menu_items.map(&:length).max + 4 # Add padding
      menu_x = [end_pos[:x], Terminal.size[1] - menu_width].min
      menu_y = [end_pos[:y] + 1, Terminal.size[0] - 5].min

      @popup_menu = UI::Components::PopupMenu.new(
        menu_x, menu_y,
        menu_items
      )
      switch_mode(:popup_menu) # Switch to dedicated popup mode
    end

    def handle_popup_action(action)
      case action
      when 'Create Annotation'
        # Important: Switch back to read mode BEFORE switching to annotation editor
        switch_mode(:read)
        switch_mode(:annotation_editor,
                    text: @selected_text,
                    range: @selection_range,
                    chapter_index: @current_chapter)
      when 'Copy to Clipboard'
        copy_to_clipboard(@selected_text)
        set_message('Copied to clipboard!')
        switch_mode(:read) # Switch back to read mode
      end

      @popup_menu = nil
      @mouse_handler.reset
      @selection_range = nil
    end

    def highlight_selection
      range = @mouse_handler.selection_range || @selection_range
      highlight_range(range, Terminal::ANSI::BG_BLUE) if range
    end

    def highlight_saved_annotations
      return unless @annotations

      @annotations.select { |a| a['chapter_index'] == @current_chapter }
                  .each do |ann|
        highlight_range(ann['range'], Terminal::ANSI::BG_CYAN)
      end
    end

    def highlight_range(range, color)
      return unless range && @rendered_lines

      start_pos = range[:start] || range['start']
      end_pos = range[:end] || range['end']
      return unless start_pos && end_pos

      start_y = start_pos[:y] || start_pos['y']
      end_y   = end_pos[:y] || end_pos['y']
      start_x = start_pos[:x] || start_pos['x']
      end_x   = end_pos[:x] || end_pos['x']
      return unless start_y && end_y && start_x && end_x

      (start_y..end_y).each do |y|
        row = y + 1
        line_info = @rendered_lines[row]
        next unless line_info

        line_text = line_info[:text].dup
        line_start_col = line_info[:col]

        start_idx = y == start_y ? start_x - line_start_col : 0
        end_idx = y == end_y ? end_x - line_start_col : line_text.length - 1

        start_idx = [[start_idx, line_text.length - 1].min, 0].max
        end_idx = [[end_idx, line_text.length - 1].min, 0].max
        next if end_idx < start_idx

        # Build the new line with highlighting
        new_line = ''
        new_line += line_text[0...start_idx] if start_idx.positive?
        new_line += "#{color}#{Terminal::ANSI::WHITE}#{line_text[start_idx..end_idx]}#{Terminal::ANSI::RESET}"
        new_line += line_text[(end_idx + 1)..] if end_idx < line_text.length - 1

        Terminal.write(row, line_start_col, new_line)
      end
    end

    def refresh_annotations
      @annotations = Annotations::AnnotationStore.get(@path)
    end

    def extract_selected_text(range)
      return '' unless range && @rendered_lines

      start_pos = range[:start]
      end_pos = range[:end]
      text = []

      (start_pos[:y]..end_pos[:y]).each do |y|
        row = y + 1 # @rendered_lines keys are 1-based row numbers
        line_info = @rendered_lines[row]
        next unless line_info

        line_text = line_info[:text]
        line_start_col = line_info[:col]

        start_char_index = y == start_pos[:y] ? start_pos[:x] - line_start_col : 0
        end_char_index = y == end_pos[:y] ? end_pos[:x] - line_start_col : line_text.length - 1

        start_char_index = [0, start_char_index].max
        end_char_index = [line_text.length - 1, end_char_index].min

        text << line_text[start_char_index..end_char_index] if end_char_index >= start_char_index
      end

      text.join("\n")
    end

    def copy_to_clipboard(text)
      cmd = case RUBY_PLATFORM
            when /darwin/ then 'pbcopy'
            when /linux/
              if system('which wl-copy > /dev/null 2>&1')
                'wl-copy'
              elsif system('which xclip > /dev/null 2>&1')
                'xclip -selection clipboard'
              end
            end

      IO.popen(cmd, 'w') { |io| io.write(text) } if cmd
    rescue StandardError
      nil
    end
  end
end
