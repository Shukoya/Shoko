# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # Mode for creating/editing annotations
    class AnnotationEditorMode < BaseMode
      def initialize(reader, text: nil, range: nil, annotation: nil, chapter_index: nil)
        super(reader)
        @annotation = annotation
        @selected_text = (text || annotation&.fetch('text', '') || '').dup
        @note = (annotation&.fetch('note', '') || '').dup
        @range = range || annotation&.fetch('range')
        @chapter_index = chapter_index || annotation&.fetch('chapter_index')
        @cursor_pos = @note.length
        @is_editing = !annotation.nil?
      end

      def draw(height, width)
        draw_header(width)
        draw_selected_text(width)
        draw_divider(width)
        draw_text_area(height, width)
        draw_footer(height)
      end

      def handle_input(key)
        case key
        when "\e" then reader.switch_mode(:read)
        when "\x13" then save_annotation # Ctrl+S
        when "\x7F", "\b" then handle_backspace
        when "\r" then handle_enter
        else handle_character(key)
        end
      end

      private

      def draw_header(_width)
        title = @is_editing ? 'Editing Annotation' : 'Creating Annotation'
        terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}#{title}#{Terminal::ANSI::RESET}")
      end

      def draw_selected_text(_width)
        text = "Selected: #{@selected_text.tr("\n", ' ')[0..60]}..."
        terminal.write(2, 2, "#{Terminal::ANSI::DIM}#{text}#{Terminal::ANSI::RESET}")
      end

      def draw_divider(width)
        terminal.write(3, 0, Terminal::ANSI::DIM + ('─' * width) + Terminal::ANSI::RESET)
      end

      def draw_text_area(height, width)
        box_y = 5
        box_height = height - 8
        box_width = width - 4

        draw_box(box_y, 2, box_height, box_width)
        draw_text_content(box_y + 1, 4, box_height - 2, box_width - 4)
      end

      def draw_box(y, x, height, width)
        # Top border
        terminal.write(y, x, "╭#{'─' * (width - 2)}╮")
        terminal.write(y, x + 2, '[ Annotation Note ]')

        # Side borders
        (1...(height - 1)).each do |i|
          terminal.write(y + i, x, '│')
          terminal.write(y + i, x + width - 1, '│')
        end

        # Bottom border
        terminal.write(y + height - 1, x, "╰#{'─' * (width - 2)}╯")
      end

      def draw_text_content(y, x, height, width)
        wrapped = word_wrap(@note, width)

        wrapped.each_with_index do |line, i|
          break if i >= height

          terminal.write(y + i, x, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
        end

        # Draw cursor
        cursor_lines = word_wrap(@note[0...@cursor_pos], width)
        cursor_y = y + cursor_lines.length - 1
        cursor_x = x + (cursor_lines.last || '').length

        terminal.write(cursor_y, cursor_x, "#{Terminal::ANSI::BRIGHT_WHITE}_#{Terminal::ANSI::RESET}")
      end

      def draw_footer(height)
        terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}Ctrl+S Save • ESC Cancel#{Terminal::ANSI::RESET}")
      end

      def save_annotation
        path = reader.instance_variable_get(:@path)

        if @is_editing && @annotation
          Annotations::AnnotationStore.update(path, @annotation['id'], @note)
        else
          Annotations::AnnotationStore.add(path, @selected_text, @note, @range, @chapter_index)
        end

        reader.refresh_annotations if reader.respond_to?(:refresh_annotations)
        reader.send(:set_message, 'Annotation saved!')
        reader.switch_mode(:read)
      end

      def handle_backspace
        return unless @cursor_pos.positive?

        @note.slice!(@cursor_pos - 1)
        @cursor_pos -= 1
      end

      def handle_enter
        @note.insert(@cursor_pos, "\n")
        @cursor_pos += 1
      end

      def handle_character(key)
        return unless key.length == 1 && key.ord >= 32 && key.ord < 127

        @note.insert(@cursor_pos, key)
        @cursor_pos += 1
      end

      def word_wrap(text, width)
        return [''] if text.empty?

        text.split("\n", -1).flat_map do |line|
          line.empty? ? [''] : line.scan(/.{1,#{width}}/)
        end
      end
    end
  end
end
