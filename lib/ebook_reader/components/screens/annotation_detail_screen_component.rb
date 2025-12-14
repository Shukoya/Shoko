# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/box_drawer'
require_relative '../ui/text_utils'

module EbookReader
  module Components
    module Screens
      # Detailed view for a single annotation selected from the list
      class AnnotationDetailScreenComponent < BaseComponent
        include Constants::UIConstants
        include UI::BoxDrawer

        def initialize(state)
          super()
          @state = state
        end

        def do_render(surface, bounds)
          width = bounds.width
          height = bounds.height
          reset = Terminal::ANSI::RESET

          ann = selected_annotation
          book_path = @state.get(%i[menu selected_annotation_book])
          book_label = book_path ? File.basename(book_path) : 'Unknown Book'

          # Header
          title_plain = "📝 Annotation • #{book_label}"
          title_width = EbookReader::Helpers::TextMetrics.visible_length(title_plain)
          title = "#{COLOR_TEXT_ACCENT}#{title_plain}#{reset}"
          surface.write(bounds, 1, 2, title)
          actions_plain = '[o] Open • [e] Edit • [d] Delete • [ESC] Back'
          actions_width = EbookReader::Helpers::TextMetrics.visible_length(actions_plain)
          min_actions_col = 2 + title_width + 2
          right_actions_col = width - actions_width
          actions_col = [right_actions_col, min_actions_col].max
          surface.write(bounds, 1, actions_col, "#{COLOR_TEXT_DIM}#{actions_plain}#{reset}")
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + reset)

          return render_empty(surface, bounds) unless ann

          # Metadata row
          meta_left = "Ch: #{safe(ann[:chapter_index])}"
          page = page_meta(ann)
          meta_mid = page ? "Page: #{page}" : nil
          date = (ann[:created_at] || ann['created_at']).to_s.tr('T', ' ').sub('Z', '')
          meta_right = "Saved: #{date}"
          meta_line = [meta_left, meta_mid, meta_right].compact.join('   ')
          surface.write(bounds, 3, 2, COLOR_TEXT_DIM + meta_line + reset)

          # Selected text box
          box_y = 5
          box_h = [height * 0.35, 8].max.to_i
          box_w = width - 4
          draw_box(surface, bounds, box_y, 2, box_h, box_w, label: 'Selected Text')
          bw = box_w - 4
          snippet_lines = UI::TextUtils.wrap_text((ann[:text] || ann['text'] || '').to_s, bw)
          snippet_lines.each_with_index do |line, i|
            break if i >= box_h - 2

            write_padded_primary(surface, bounds, box_y + 1 + i, 4, line, bw)
          end

          # Note box
          note_y = box_y + box_h + 2
          note_h = [height - note_y - 3, 6].max
          draw_box(surface, bounds, note_y, 2, note_h, box_w, label: 'Note')
          note_lines = UI::TextUtils.wrap_text((ann[:note] || ann['note'] || '').to_s, bw)
          note_lines.each_with_index do |line, i|
            break if i >= note_h - 2

            write_padded_primary(surface, bounds, note_y + 1 + i, 4, line, bw)
          end
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def write_padded_primary(surface, bounds, row, col, text, width)
          reset = Terminal::ANSI::RESET
          padded = UI::TextUtils.pad_right(text, width)
          surface.write(bounds, row, col, COLOR_TEXT_PRIMARY + padded + reset)
        end

        def selected_annotation
          ann = @state.get(%i[menu selected_annotation])
          # symbolize shallow keys for convenience
          return unless ann.is_a?(Hash)

          ann.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
        end

        def page_meta(ann)
          curr = ann[:page_current] || ann['page_current']
          total = ann[:page_total] || ann['page_total']
          mode = (ann[:page_mode] || ann['page_mode']).to_s
          return nil unless curr && total

          label = mode.empty? ? '' : "#{mode}: "
          "#{label}#{curr}/#{total}"
        end

        # draw_box and wrap_text are provided by included UI modules

        def safe(val)
          val.nil? ? '-' : val
        end
      end
    end
  end
end
