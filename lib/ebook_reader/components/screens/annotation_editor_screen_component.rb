# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Reader-context annotation editor as a proper component
      # Replaces ReaderModes::AnnotationEditorMode
      class AnnotationEditorScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(ui_controller, text: nil, range: nil, annotation: nil, chapter_index: nil, dependencies: nil)
          super(dependencies)
          @ui = ui_controller
          @dependencies = dependencies
          @annotation = annotation
          @selected_text = (text || annotation&.fetch('text', '') || '').dup
          @note = (annotation&.fetch('note', '') || '').dup
          @range = range || annotation&.fetch('range')
          @chapter_index = chapter_index || annotation&.fetch('chapter_index')
          @cursor_pos = @note.length
          @is_editing = !annotation.nil?
        end

        def do_render(surface, bounds)
          width = bounds.width
          height = bounds.height

          # Header
          title = @is_editing ? 'Editing Annotation' : 'Creating Annotation'
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}#{title}#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [width - 28, title.length + 2].max,
                        "#{COLOR_TEXT_DIM}[Ctrl+S] Save • [ESC] Cancel#{Terminal::ANSI::RESET}")
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + Terminal::ANSI::RESET)

          # Selected text (read-only)
          box_y = 4
          box_h = [height * 0.25, 6].max.to_i
          box_w = width - 4
          draw_box(surface, bounds, box_y, 2, box_h, box_w, label: 'Selected Text')
          wrap_text(@selected_text.to_s.tr("\n", ' '), box_w - 4).each_with_index do |line, i|
            break if i >= box_h - 2
            surface.write(bounds, box_y + 1 + i, 4,
                          COLOR_TEXT_PRIMARY + line.ljust(box_w - 4) + Terminal::ANSI::RESET)
          end

          # Note editor
          note_y = box_y + box_h + 2
          note_h = [height - note_y - 3, 6].max
          draw_box(surface, bounds, note_y, 2, note_h, box_w, label: 'Note (editable)')

          wrapped = wrap_text(@note, box_w - 4)
          wrapped.each_with_index do |line, i|
            break if i >= note_h - 2
            surface.write(bounds, note_y + 1 + i, 4,
                          COLOR_TEXT_PRIMARY + line.ljust(box_w - 4) + Terminal::ANSI::RESET)
          end

          # Cursor
          cursor_lines = wrap_text(@note[0...@cursor_pos], box_w - 4)
          c_row = note_y + 1 + [cursor_lines.length - 1, 0].max
          c_col = 4 + (cursor_lines.last || '').length
          surface.write(bounds, c_row, c_col, "#{SELECTION_HIGHLIGHT}_#{Terminal::ANSI::RESET}")

          # Footer
          surface.write(bounds, height - 1, 2,
                        "#{COLOR_TEXT_DIM}[Type] to edit • [Backspace] delete • [Enter] newline#{Terminal::ANSI::RESET}")
        end

        # Public API used by InputController bindings
        def save_annotation
          path = @ui.current_book_path
          return unless path

          svc = @dependencies&.resolve(:annotation_service)
          return unless svc

          if @is_editing && @annotation
            svc.update(path, @annotation['id'], @note)
          else
            svc.add(path, @selected_text, @note, @range, @chapter_index, nil)
          end

          @ui.refresh_annotations
          @ui.cleanup_popup_state
          @ui.set_message('Annotation saved!')
          @ui.switch_mode(:read)
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
          return unless key.to_s.length == 1 && key.ord >= 32 && key.ord < 127
          @note.insert(@cursor_pos, key)
          @cursor_pos += 1
        end

        private

        def draw_box(surface, bounds, y, x, h, w, label: nil)
          surface.write(bounds, y, x, "╭#{'─' * (w - 2)}╮")
          surface.write(bounds, y, x + 2, "[ #{label} ]") if label
          (1...(h - 1)).each do |i|
            surface.write(bounds, y + i, x, '│')
            surface.write(bounds, y + i, x + w - 1, '│')
          end
          surface.write(bounds, y + h - 1, x, "╰#{'─' * (w - 2)}╯")
        end

        def wrap_text(text, width)
          return [''] if text.nil? || text.empty?
          text.split("\n", -1).flat_map { |line| line.empty? ? [''] : line.scan(/.{1,#{width}}/) }
        end
      end
    end
  end
end
