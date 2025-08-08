# frozen_string_literal: true

require_relative '../../terminal'
require_relative '../../annotations/annotation_store'

module EbookReader
  module UI
    module Screens
      # A screen for editing an annotation's note.
      class AnnotationEditorScreen
        attr_accessor :note, :cursor_pos

        def initialize
          @annotation = nil
          @note = ''
          @cursor_pos = 0
        end

        def set_annotation(annotation, book_path)
          @annotation = annotation
          @book_path = book_path
          @note = annotation['note'].dup
          @cursor_pos = @note.length
        end

        def draw(_height, width)
          Terminal.clear
          draw_header(width)
          draw_note_editor(width)
          draw_footer(width)
        end

        def handle_input(key)
          case key
          when "\u0013" # Ctrl+S
            save
            return :saved
          when "\e" # Escape
            return :cancelled
          when "\u007F", "\b" # Backspace
            handle_backspace
          else
            handle_character(key)
          end
          :no_action
        end

        private

        def draw_header(width)
          Terminal.write(1, 2, "#{Terminal::ANSI::BOLD}Editing Annotation#{Terminal::ANSI::RESET}")
          Terminal.write(2, 4, "#{Terminal::ANSI::DIM}#{@annotation['text'][0, width - 8]}...#{Terminal::ANSI::RESET}")
          Terminal.write(3, 0, Terminal::ANSI::DIM + ('─' * width) + Terminal::ANSI::RESET)
        end

        def draw_note_editor(_width)
          Terminal.write(5, 2, 'Note:')
          Terminal.write(6, 4, @note)
          Terminal.write(6, 4 + @cursor_pos, "#{Terminal::ANSI::BRIGHT_WHITE}_#{Terminal::ANSI::RESET}")
        end

        def draw_footer(width)
          footer_text = 'Ctrl+S: Save | Esc: Cancel'
          Terminal.write(10, 2, Terminal::ANSI::DIM + footer_text + Terminal::ANSI::RESET)
          Terminal.write(9, 0, Terminal::ANSI::DIM + ('─' * width) + Terminal::ANSI::RESET)
        end

        def handle_backspace
          return if @cursor_pos.zero?

          @note.slice!(@cursor_pos - 1)
          @cursor_pos -= 1
        end

        def handle_character(key)
          return unless key.length == 1 && key.ord >= 32 && key.ord < 127

          @note.insert(@cursor_pos, key)
          @cursor_pos += 1
        end

        def save
          return unless @annotation && @book_path

          Annotations::AnnotationStore.update(@book_path, @annotation['id'], @note)
        end
      end
    end
  end
end
