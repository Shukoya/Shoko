# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/box_drawer'
require_relative '../ui/text_utils'

module EbookReader
  module Components
    module Screens
      # Simple annotation note editor within the menu (no book load)
      class AnnotationEditScreenComponent < BaseComponent
        include Constants::UIConstants
        include UI::BoxDrawer

        def initialize(state, dependencies = nil)
          super(dependencies)
          @state = state
          @dependencies = dependencies
        end

        def do_render(surface, bounds)
          width = bounds.width
          height = bounds.height
          reset = Terminal::ANSI::RESET

          ann = @state.get(%i[menu selected_annotation]) || {}
          book_path = @state.get(%i[menu selected_annotation_book])
          book_label = book_path ? File.basename(book_path) : 'Unknown Book'

          title = "#{COLOR_TEXT_ACCENT}📝 Edit Annotation • #{book_label}#{reset}"
          surface.write(bounds, 1, 2, title)
          surface.write(bounds, 1, [width - 28, title.length + 2].max,
                        "#{COLOR_TEXT_DIM}[Ctrl+S] Save • [ESC] Cancel#{reset}")
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + reset)

          # Snippet (read-only)
          box_y = 4
          box_h = [height * 0.25, 6].max.to_i
          box_w = width - 4
          draw_box(surface, bounds, box_y, 2, box_h, box_w, label: 'Selected Text')
          bw = box_w - 4
          UI::TextUtils.wrap_text((ann[:text] || ann['text'] || '').to_s, bw).each_with_index do |line, i|
            break if i >= box_h - 2

            write_padded_primary(surface, bounds, box_y + 1 + i, 4, line, bw)
          end

          # Note editor
          note_y = box_y + box_h + 2
          note_h = [height - note_y - 3, 6].max
          draw_box(surface, bounds, note_y, 2, note_h, box_w, label: 'Note (editable)')

          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          cursor = (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
          lines = UI::TextUtils.wrap_text(text, bw)
          base_row = note_y + 1
          lines.each_with_index do |line, i|
            break if i >= note_h - 2

            write_padded_primary(surface, bounds, base_row + i, 4, line, bw)
          end

          # Cursor position
          cursor_lines = UI::TextUtils.wrap_text(text[0, cursor], bw)
          c_row = base_row + [cursor_lines.length - 1, 0].max
          c_col = 4 + (cursor_lines.last || '').length
          surface.write(bounds, c_row, c_col, "#{SELECTION_HIGHLIGHT}_#{reset}")

          # Footer
          surface.write(bounds, height - 1, 2,
                        "#{COLOR_TEXT_DIM}[Type] to edit • [Backspace] delete • [Enter] newline#{reset}")
        end

        def preferred_height(_available_height)
          :fill
        end

        # --- Unified editor API (used by Domain::Commands) ---
        def save_annotation
          ann = @state.get(%i[menu selected_annotation]) || {}
          path = @state.get(%i[menu selected_annotation_book])
          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          ann_id = ann[:id] || ann['id']
          return unless path && ann_id

          begin
            svc = @dependencies&.resolve(:annotation_service)
            svc&.update(path, ann_id, text)
            # Refresh annotations mapping for list view if possible
            @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(annotations_all: svc.list_all)) if svc
          rescue StandardError
            # ignore; best-effort
          end

          # Return to annotations list
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :annotations))
        end

        def handle_backspace
          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          cur = (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
          return unless cur.positive?

          new_text = text.dup
          prev = cur - 1
          new_text.slice!(prev)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                            annotation_edit_text: new_text,
                            annotation_edit_cursor: prev
                          ))
        end

        def handle_enter
          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          cur = (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
          new_text = text.dup
          new_text.insert(cur, "\n")
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                            annotation_edit_text: new_text,
                            annotation_edit_cursor: cur + 1
                          ))
        end

        def handle_character(char)
          return unless char.to_s.length == 1 && char.ord >= 32

          text = (@state.get(%i[menu annotation_edit_text]) || '').to_s
          cur = (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
          new_text = text.dup
          new_text.insert(cur, char)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                            annotation_edit_text: new_text,
                            annotation_edit_cursor: cur + 1
                          ))
        end

        private

        def write_padded_primary(surface, bounds, row, col, text, width)
          reset = Terminal::ANSI::RESET
          padded = text.ljust(width)
          surface.write(bounds, row, col, COLOR_TEXT_PRIMARY + padded + reset)
        end
      end
    end
  end
end
