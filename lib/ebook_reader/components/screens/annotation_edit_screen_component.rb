# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Simple annotation note editor within the menu (no book load)
      class AnnotationEditScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(state)
          super()
          @state = state
        end

        def do_render(surface, bounds)
          width = bounds.width
          height = bounds.height

          ann = @state.get(%i[menu selected_annotation]) || {}
          book_path = @state.get(%i[menu selected_annotation_book])
          book_label = book_path ? File.basename(book_path) : 'Unknown Book'

          title = "#{COLOR_TEXT_ACCENT}📝 Edit Annotation • #{book_label}#{Terminal::ANSI::RESET}"
          surface.write(bounds, 1, 2, title)
          surface.write(bounds, 1, [width - 28, title.length + 2].max,
                        "#{COLOR_TEXT_DIM}[Ctrl+S] Save • [ESC] Cancel#{Terminal::ANSI::RESET}")
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + Terminal::ANSI::RESET)

          # Snippet (read-only)
          box_y = 4
          box_h = [height * 0.25, 6].max.to_i
          box_w = width - 4
          draw_box(surface, bounds, box_y, 2, box_h, box_w, label: 'Selected Text')
          wrap_text((ann[:text] || ann['text'] || '').to_s,
                    box_w - 4).each_with_index do |line, i|
            break if i >= box_h - 2

            surface.write(bounds, box_y + 1 + i, 4,
                          COLOR_TEXT_PRIMARY + line.ljust(box_w - 4) + Terminal::ANSI::RESET)
          end

          # Note editor
          note_y = box_y + box_h + 2
          note_h = [height - note_y - 3, 6].max
          draw_box(surface, bounds, note_y, 2, note_h, box_w, label: 'Note (editable)')

          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          cursor = (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
          lines = wrap_text(text, box_w - 4)
          lines.each_with_index do |line, i|
            break if i >= note_h - 2

            surface.write(bounds, note_y + 1 + i, 4,
                          COLOR_TEXT_PRIMARY + line.ljust(box_w - 4) + Terminal::ANSI::RESET)
          end

          # Cursor position
          cursor_lines = wrap_text(text[0, cursor], box_w - 4)
          c_row = note_y + 1 + [cursor_lines.length - 1, 0].max
          c_col = 4 + (cursor_lines.last || '').length
          surface.write(bounds, c_row, c_col, "#{SELECTION_HIGHLIGHT}_#{Terminal::ANSI::RESET}")

          # Footer
          surface.write(bounds, height - 1, 2,
                        "#{COLOR_TEXT_DIM}[Type] to edit • [Backspace] delete • [Enter] newline#{Terminal::ANSI::RESET}")
        end

        def preferred_height(_available_height)
          :fill
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
          return [''] if text.empty?

          text.split("\n", -1).flat_map { |line| line.empty? ? [''] : line.scan(/.{1,#{width}}/) }
        end
      end
    end
  end
end
