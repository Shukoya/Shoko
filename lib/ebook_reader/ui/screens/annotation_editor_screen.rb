# frozen_string_literal: true

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

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          draw_header(surface, bounds, width)
          draw_note_editor(surface, bounds)
          draw_footer(surface, bounds, width)
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

        def draw_header(surface, bounds, width)
          surface.write(bounds, 1, 2, Terminal::ANSI::BOLD + 'Editing Annotation' + Terminal::ANSI::RESET)
          surface.write(bounds, 2, 4, Terminal::ANSI::DIM + (@annotation['text'][0, width - 8]).to_s + '...' + Terminal::ANSI::RESET)
          surface.write(bounds, 3, 1, Terminal::ANSI::DIM + ('─' * (width - 1)) + Terminal::ANSI::RESET)
        end

        def draw_note_editor(surface, bounds)
          surface.write(bounds, 5, 2, 'Note:')
          surface.write(bounds, 6, 4, @note)
          surface.write(bounds, 6, 4 + @cursor_pos, Terminal::ANSI::BRIGHT_WHITE + '_' + Terminal::ANSI::RESET)
        end

        def draw_footer(surface, bounds, width)
          footer_text = 'Ctrl+S: Save | Esc: Cancel'
          surface.write(bounds, 10, 2, Terminal::ANSI::DIM + footer_text + Terminal::ANSI::RESET)
          surface.write(bounds, 9, 1, Terminal::ANSI::DIM + ('─' * (width - 1)) + Terminal::ANSI::RESET)
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
require_relative '../../components/surface'
require_relative '../../components/rect'
