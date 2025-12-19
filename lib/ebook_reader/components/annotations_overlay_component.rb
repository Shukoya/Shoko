# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/box_drawer'
require_relative 'ui/text_utils'
require_relative 'ui/list_helpers'

module EbookReader
  module Components
    # Centered overlay listing annotations above the reading surface.
    class AnnotationsOverlayComponent < BaseComponent
      include Constants::UIConstants
      include UI::BoxDrawer

      def initialize(state)
        super()
        @state = state
        @visible = true
        @selected_index = (@state.get(%i[reader sidebar_annotations_selected]) || 0).to_i
      end

      def visible?
        @visible
      end

      def hide
        @visible = false
      end

      def selected_index=(index)
        @selected_index = index.to_i
      end

      def handle_key(key)
        entries = annotations
        return { type: :close } if entries.empty? && cancel_key?(key)

        if up_key?(key)
          move_selection(-1)
        elsif down_key?(key)
          move_selection(1)
        elsif confirm_key?(key)
          annotation = current_annotation
          annotation ? { type: :open, annotation: annotation } : nil
        elsif edit_key?(key)
          annotation = current_annotation
          annotation ? { type: :edit, annotation: annotation } : nil
        elsif delete_key?(key)
          annotation = current_annotation
          annotation ? { type: :delete, annotation: annotation } : nil
        elsif cancel_key?(key)
          { type: :close }
        end
      end

      def current_annotation
        entries = annotations
        entries.empty? ? nil : entries[@selected_index]
      end

      def render(surface, bounds)
        do_render(surface, bounds)
      end

      def do_render(surface, bounds)
        return unless @visible

        entries = annotations
        overlay_width = calculate_width(bounds.width)
        overlay_height = calculate_height(bounds.height)
        origin_x = [(bounds.width - overlay_width) / 2, 1].max + 1
        origin_y = [(bounds.height - overlay_height) / 2, 1].max + 1

        fill_background(surface, bounds, origin_x, origin_y, overlay_width, overlay_height)
        draw_box(surface, bounds, origin_y, origin_x, overlay_height, overlay_width, label: 'Annotations')
        draw_header(surface, bounds, origin_x, origin_y, overlay_width, entries.length)
        draw_list(surface, bounds, origin_x, origin_y, overlay_width, overlay_height, entries)
        draw_footer(surface, bounds, origin_x, origin_y, overlay_width, overlay_height)
      end

      private

      def annotations
        @annotations = (@state.get(%i[reader annotations]) || []).map { |ann| symbolize_keys(ann) }
        clamp_selection!
        @annotations
      end

      def clamp_selection!
        count = @annotations.length
        @selected_index = if count.zero?
                            0
                          else
                            @selected_index.clamp(0, count - 1)
                          end
      end

      def move_selection(delta)
        entries = annotations
        return if entries.empty?

        new_index = (@selected_index + delta).clamp(0, entries.length - 1)
        return if new_index == @selected_index

        @selected_index = new_index
        { type: :selection_change, index: @selected_index }
      end

      def draw_header(surface, bounds, origin_x, origin_y, width, count)
        reset = Terminal::ANSI::RESET
        title = "#{COLOR_TEXT_ACCENT}📝 Annotations (#{count})#{reset}"
        surface.write(bounds, origin_y + 1, origin_x + 2, title)

        info_plain = '[Enter] Open • [e] Edit • [d] Delete • [Esc] Close'
        info_col = origin_x + [width - EbookReader::Helpers::TextMetrics.visible_length(info_plain) - 2, 2].max
        surface.write(bounds, origin_y + 1, info_col, "#{COLOR_TEXT_DIM}#{info_plain}#{reset}")
      end

      def draw_list(surface, bounds, origin_x, origin_y, width, height, entries)
        inner_width = width - 4
        list_top = origin_y + 3
        list_height = height - 5
        list_height = 1 if list_height.negative?

        if entries.empty?
          message = "#{COLOR_TEXT_DIM}No annotations yet#{Terminal::ANSI::RESET}"
          row = origin_y + (height / 2)
          col = origin_x + [(width - EbookReader::Helpers::TextMetrics.visible_length(message)) / 2, 2].max
          surface.write(bounds, row, col, message)
          return
        end

        idx_width = 4
        date_width = [12, inner_width / 5].max
        remaining = inner_width - idx_width - date_width - 2
        remaining = 12 if remaining < 12
        snippet_width = [(remaining * 0.6).floor, 8].max
        note_width = [remaining - snippet_width, 6].max

        header = [
          '  ',
          UI::TextUtils.pad_right('#', idx_width),
          ' ',
          UI::TextUtils.pad_right('Snippet', snippet_width),
          ' ',
          UI::TextUtils.pad_right('Note', note_width),
          ' ',
          UI::TextUtils.pad_right('Saved', date_width),
        ].join
        surface.write(bounds, list_top - 1, origin_x + 2,
                      "#{COLOR_TEXT_DIM}#{header}#{Terminal::ANSI::RESET}")

        start_index, visible = UI::ListHelpers.slice_visible(entries, list_height, @selected_index)
        visible.each_with_index do |annotation, offset|
          line_row = list_top + offset
          pointer = (start_index + offset) == @selected_index ? '▸' : ' '
          line_color = (start_index + offset) == @selected_index ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
          snippet = UI::TextUtils.pad_right(
            UI::TextUtils.truncate_text(annotation[:text].to_s.tr("\n", ' '), snippet_width), snippet_width
          )
          note = UI::TextUtils.pad_right(UI::TextUtils.truncate_text(annotation[:note].to_s.tr("\n", ' '), note_width),
                                         note_width)
          saved_at = annotation[:updated_at] || annotation[:created_at]
          saved_text = saved_at ? saved_at.to_s.split('T').first : '-'
          saved = UI::TextUtils.pad_right(UI::TextUtils.truncate_text(saved_text, date_width), date_width)

          idx_text = UI::TextUtils.pad_right((start_index + offset + 1).to_s, idx_width)
          line = [pointer, ' ', idx_text, ' ', snippet, ' ', note, ' ', saved].join
          surface.write(bounds, line_row, origin_x + 2,
                        "#{line_color}#{line}#{Terminal::ANSI::RESET}")
        end
      end

      def draw_footer(surface, bounds, origin_x, origin_y, _width, height)
        hint = "#{COLOR_TEXT_DIM}Use ↑/↓ to navigate • Enter to open#{Terminal::ANSI::RESET}"
        surface.write(bounds, origin_y + height - 2, origin_x + 2, hint)
      end

      def fill_background(surface, bounds, origin_x, origin_y, width, height)
        bg = POPUP_BG_DEFAULT
        reset = Terminal::ANSI::RESET
        height.times do |offset|
          surface.write(bounds, origin_y + offset, origin_x, "#{bg}#{' ' * width}#{reset}")
        end
      end

      def calculate_width(total_width)
        base = [(total_width * 0.6).floor, total_width - 8].min
        upper = total_width - 8
        lower = [48, upper].min
        base.clamp(lower, upper)
      end

      def calculate_height(total_height)
        base = [(total_height * 0.5).floor, total_height - 6].min
        upper = total_height - 6
        lower = [12, upper].min
        base.clamp(lower, upper)
      end

      def up_key?(key)
        EbookReader::Input::KeyDefinitions::NAVIGATION[:up].include?(key)
      end

      def down_key?(key)
        EbookReader::Input::KeyDefinitions::NAVIGATION[:down].include?(key)
      end

      def confirm_key?(key)
        EbookReader::Input::KeyDefinitions::ACTIONS[:confirm].include?(key)
      end

      def cancel_key?(key)
        EbookReader::Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
      end

      def edit_key?(key)
        %w[e E].include?(key)
      end

      def delete_key?(key)
        key == 'd'
      end

      def symbolize_keys(annotation)
        return annotation unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end
    end
  end
end
