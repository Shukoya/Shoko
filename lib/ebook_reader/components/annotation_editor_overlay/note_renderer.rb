# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../../helpers/text_metrics'
require_relative '../../terminal'

module EbookReader
  module Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Renders note contents and cursor inside the annotation editor overlay.
      class NoteRenderer
        def initialize(background:, text_color:, cursor_color:, geometry:)
          @background = background
          @text_color = text_color
          @cursor_color = cursor_color
          @geometry = geometry
        end

        def render(surface, bounds, note:, cursor_pos:)
          wrapped_note = wrap_lines(note, @geometry.text_width)
          cursor_lines = wrap_lines(note[0...cursor_pos], @geometry.text_width)
          cursor_line_index = [cursor_lines.length - 1, 0].max

          visible_start, visible_lines = visible_window(wrapped_note, cursor_line_index, @geometry.note_rows)
          render_lines(surface, bounds, visible_lines)
          cursor_row, cursor_col = cursor_position(cursor_lines, cursor_line_index, visible_start)
          render_cursor(surface, bounds, cursor_row, cursor_col)
        end

        private

        def wrap_lines(text, width)
          lines = UI::TextUtils.wrap_text(text.to_s, width)
          lines.empty? ? [''] : lines
        end

        def visible_window(lines, cursor_line_index, note_rows)
          max_start = [lines.length - note_rows, 0].max
          visible_start = [cursor_line_index - note_rows + 1, 0].max
          visible_start = [visible_start, max_start].min
          visible_lines = lines[visible_start, note_rows] || []
          visible_lines += Array.new(note_rows - visible_lines.length, '')
          [visible_start, visible_lines]
        end

        def render_lines(surface, bounds, lines)
          lines.each_with_index do |line, idx|
            row = @geometry.note_top + idx
            padded = UI::TextUtils.pad_right(line, @geometry.text_width)
            surface.write(bounds, row, @geometry.text_x,
                          "#{@background}#{@text_color}#{padded}#{Terminal::ANSI::RESET}")
          end
        end

        def cursor_position(cursor_lines, cursor_line_index, visible_start)
          cursor_display_row = (cursor_line_index - visible_start).clamp(0, @geometry.note_rows - 1)
          cursor_row = @geometry.note_top + cursor_display_row
          cursor_line = cursor_lines.last || ''
          cursor_col = @geometry.text_x + [EbookReader::Helpers::TextMetrics.visible_length(cursor_line),
                                           @geometry.text_width - 1].min
          [cursor_row, cursor_col]
        end

        def render_cursor(surface, bounds, cursor_row, cursor_col)
          surface.write(bounds, cursor_row, cursor_col, "#{@cursor_color}_#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
