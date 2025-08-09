# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'annotations/mouse_handler'
require_relative 'annotations/annotation_store'
require_relative 'ui/components/popup_menu'
require_relative 'reader_modes/annotation_editor_mode'
require_relative 'reader_modes/annotations_mode'
require_relative 'terminal_mouse_patch'

module EbookReader
  # A Reader that supports mouse interactions for annotations.
  class MouseableReader < ReaderController
    def initialize(epub_path, config = Config.new)
      super
      @mouse_handler = Annotations::MouseHandler.new
      @popup_menu = nil
      @selected_text = nil
      @state.selection = nil
      @rendered_lines = {}
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
      @rendered_lines.clear
      super

      # Overlays for mouse selection/annotations (reading and popup menu)
      if [:read, :popup_menu].include?(@state.mode)
        highlight_saved_annotations
        highlight_selection if @mouse_handler.selecting || @state.selection
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

      if @popup_menu&.visible && event[:released]
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
      item = @popup_menu.handle_click(event[:x], event[:y])

      if item
        handle_popup_action(item)
      else
        @popup_menu = nil
        @mouse_handler.reset
        @state.selection = nil
      end
      draw_screen
    end

    def refresh_highlighting
      height, width = Terminal.size
      # Re-render content area only
      super
      highlight_saved_annotations
      highlight_selection
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

      end_pos = @state.selection[:end]
      menu_items = ['Create Annotation', 'Copy to Clipboard']
      menu_width = menu_items.map(&:length).max + 4
      menu_x = [end_pos[:x], Terminal.size[1] - menu_width].min
      menu_y = [end_pos[:y] + 1, Terminal.size[0] - 5].min

      @popup_menu = UI::Components::PopupMenu.new(menu_x, menu_y, menu_items)
      switch_mode(:popup_menu)
      # Draw immediately so the menu appears in full without extra input
      draw_screen
    end

    def handle_popup_action(action)
      case action
      when 'Create Annotation'
        switch_mode(:read)
        switch_mode(:annotation_editor,
                    text: @selected_text,
                    range: @state.selection,
                    chapter_index: @state.current_chapter)
      when 'Copy to Clipboard'
        copy_to_clipboard(@selected_text)
        set_message('Copied to clipboard!')
        switch_mode(:read)
      end

      @popup_menu = nil
      @mouse_handler.reset
      @state.selection = nil
    end

    def highlight_selection
      range = @mouse_handler.selection_range || @state.selection
      highlight_range(range, Terminal::ANSI::BG_BLUE) if range
    end

    def highlight_saved_annotations
      return unless @annotations

      @annotations.select { |a| a['chapter_index'] == @state.current_chapter }
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

      surface = Components::Surface.new(Terminal)
      bounds = Components::Rect.new(x: 1, y: 1, width: Terminal.size[1], height: Terminal.size[0])
      (start_y..end_y).each do |y|
        row = y + 1
        line_info = @rendered_lines[row]
        next unless line_info

        line_text = line_info[:text].dup
        line_start_col = line_info[:col]

        start_idx = (y == start_y ? start_x - line_start_col : 0).clamp(0, line_text.length - 1)
        end_idx = (y == end_y ? end_x - line_start_col : line_text.length - 1).clamp(0,
                                                                                     line_text.length - 1)
        next if end_idx < start_idx

        new_line = ''
        new_line += line_text[0...start_idx] if start_idx.positive?
        new_line += "#{color}#{Terminal::ANSI::WHITE}#{line_text[start_idx..end_idx]}#{Terminal::ANSI::RESET}"
        new_line += line_text[(end_idx + 1)..] if end_idx < line_text.length - 1

        surface.write(bounds, row, line_start_col, new_line)
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
        row = y + 1
        line_info = @rendered_lines[row]
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
