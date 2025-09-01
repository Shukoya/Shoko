# frozen_string_literal: true

require_relative 'base_mode'
require_relative '../components/surface'
require_relative '../components/rect'

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
        # Legacy compatibility wrapper
        surface = Components::Surface.new(Terminal)
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        render(surface, bounds)
      end

      def render(surface, bounds)
        draw_header(surface, bounds)
        draw_selected_text(surface, bounds)
        draw_divider(surface, bounds)
        draw_text_area(surface, bounds)
        draw_footer(surface, bounds)
      end

      def handle_input(key)
        return unless key

        handlers = input_handlers
        (handlers[key] || handlers[:__default__])&.call(key)
      end

      def input_handlers
        @input_handlers ||= begin
          h = {
            "\e" => lambda { |_|
              # Cancel: clear any active selection/popup and return to read mode
              reader.cleanup_popup_state if reader.respond_to?(:cleanup_popup_state)
              reader.switch_mode(:read)
              reader.draw_screen
            },
            "\x13" => ->(_) { save_annotation },
            "\x7F" => ->(_) { handle_backspace },
            "\b" => ->(_) { handle_backspace },
            "\r" => ->(_) { handle_enter },
          }
          h[:__default__] = ->(k) { handle_character(k) }
          h
        end
      end

      private

      def draw_header(surface, bounds)
        title = @is_editing ? 'Editing Annotation' : 'Creating Annotation'
        surface.write(bounds, 1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}#{title}#{Terminal::ANSI::RESET}")
      end

      def draw_selected_text(surface, bounds)
        text = "Selected: #{@selected_text.tr("\n", ' ')[0..60]}..."
        surface.write(bounds, 2, 2, "#{Terminal::ANSI::DIM}#{text}#{Terminal::ANSI::RESET}")
      end

      def draw_divider(surface, bounds)
        surface.write(bounds, 3, 1, Terminal::ANSI::DIM + ('─' * bounds.width) + Terminal::ANSI::RESET)
      end

      def draw_text_area(surface, bounds)
        box_y = 5
        box_height = bounds.height - 8
        box_width = bounds.width - 4

        draw_box(surface, bounds, box_y, 2, box_height, box_width)
        draw_text_content(surface, bounds, box_y + 1, 4, box_height - 2, box_width - 4)
      end

      def draw_box(surface, bounds, y, x, height, width)
        # Top border
        surface.write(bounds, y, x, "╭#{'─' * (width - 2)}╮")
        surface.write(bounds, y, x + 2, '[ Annotation Note ]')

        # Side borders
        (1...(height - 1)).each do |i|
          surface.write(bounds, y + i, x, '│')
          surface.write(bounds, y + i, x + width - 1, '│')
        end

        # Bottom border
        surface.write(bounds, y + height - 1, x, "╰#{'─' * (width - 2)}╯")
      end

      def draw_text_content(surface, bounds, y, x, height, width)
        wrapped = word_wrap(@note, width)

        wrapped.each_with_index do |line, i|
          break if i >= height

          surface.write(bounds, y + i, x, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
        end

        # Draw cursor
        cursor_lines = word_wrap(@note[0...@cursor_pos], width)
        cursor_y = y + cursor_lines.length - 1
        cursor_x = x + (cursor_lines.last || '').length

        surface.write(bounds, cursor_y, cursor_x, "#{Terminal::ANSI::BRIGHT_WHITE}_#{Terminal::ANSI::RESET}")
      end

      def draw_footer(surface, bounds)
        surface.write(bounds, bounds.height - 1, 2,
                      "#{Terminal::ANSI::DIM}Ctrl+S Save • ESC Cancel#{Terminal::ANSI::RESET}")
      end

      def save_annotation
        # Resolve current book path from UI controller/state rather than ivars
        path = if reader.respond_to?(:current_book_path)
                 reader.current_book_path
               else
                 # Fallback: attempt to read from state if exposed
                 begin
                   st = reader.instance_variable_get(:@state)
                   st&.get(%i[reader book_path])
                 rescue StandardError
                   nil
                 end
               end
        return unless path

        if @is_editing && @annotation
          Annotations::AnnotationStore.update(path, @annotation['id'], @note)
        else
          Annotations::AnnotationStore.add(path, @selected_text, @note, @range, @chapter_index)
        end

        # Update UI/state and clear any active selection overlays
        reader.refresh_annotations if reader.respond_to?(:refresh_annotations)
        reader.cleanup_popup_state if reader.respond_to?(:cleanup_popup_state)
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

      public :handle_character, :handle_backspace, :handle_enter, :save_annotation
    end
  end
end
