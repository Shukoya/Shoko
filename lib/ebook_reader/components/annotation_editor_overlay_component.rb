# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/box_drawer'
require_relative 'ui/text_utils'
require_relative '../input/key_definitions'

module EbookReader
  module Components
    # Overlay for creating/editing annotations without leaving the reader view.
    class AnnotationEditorOverlayComponent < BaseComponent
      include Constants::UIConstants
      include UI::BoxDrawer

      SAVE_KEYS = ["\x13"].freeze # Ctrl+S
      BACKSPACE_KEYS = ["\x08", "\x7F", '\b'].freeze
      SAVE_BUTTON_BG = "\e[48;2;69;173;130m"
      CANCEL_BUTTON_BG = "\e[48;2;191;97;106m"
      BUTTON_FG = Terminal::ANSI::BRIGHT_WHITE

      attr_reader :visible, :selected_text, :note, :chapter_index

      def initialize(selected_text:, range:, chapter_index:, annotation: nil)
        super()
        @selected_text = (selected_text || '').dup
        @range = range
        @chapter_index = chapter_index
        @annotation = annotation
        @note = if annotation
                  (annotation[:note] || annotation['note'] || '').dup
                else
                  ''.dup
                end
        @cursor_pos = @note.length
        @visible = true
      end

      def visible?
        @visible
      end

      def hide
        @visible = false
      end

      def annotation_id
        return nil unless @annotation.is_a?(Hash)

        @annotation[:id] || @annotation['id']
      end

      def selection_range
        @range
      end

      def render(surface, bounds)
        do_render(surface, bounds)
      end

      def do_render(surface, bounds)
        return unless @visible

        width = calculate_width(bounds.width)
        height = calculate_height(bounds.height)
        origin_x = bounds.x + [(bounds.width - width) / 2, 1].max
        origin_y = bounds.y + [(bounds.height - height) / 2, 1].max

        @button_regions = {}

        fill_background(surface, bounds, origin_x, origin_y, width, height)
        geometry = build_geometry(origin_x, origin_y, width, height)
        draw_box(surface, bounds, origin_y, origin_x, height, width, label: 'Annotation')

        draw_note_editor(surface, bounds, geometry)
        draw_footer(surface, bounds, geometry)
      end

      # Handles key input, returning an event hash when an action should be taken.
      def handle_key(key)
        return { type: :cancel } if cancel_key?(key)
        return handle_save if save_key?(key)

        case key
        when *BACKSPACE_KEYS
          handle_backspace
        when "\r", "\n"
          insert_newline
        else
          insert_character(key)
        end
        nil
      end

      def calculate_width(total_width)
        base = [(total_width * 0.7).floor, total_width - 6].min
        [[base, 50].max, total_width - 6].min
      end

      def calculate_height(total_height)
        base = [(total_height * 0.6).floor, total_height - 6].min
        [[base, 14].max, total_height - 6].min
      end

      def fill_background(surface, bounds, origin_x, origin_y, width, height)
        reset = Terminal::ANSI::RESET
        bg = POPUP_BG_DEFAULT
        height.times do |offset|
          surface.write(bounds, origin_y + offset, origin_x, "#{bg}#{' ' * width}#{reset}")
        end
      end

      def draw_note_editor(surface, bounds, geometry)
        text_x = geometry[:text_x]
        text_width = geometry[:text_width]
        note_rows = geometry[:note_rows]
        note_top = geometry[:box_y] + 1

        note_rows.times do |offset|
          surface.write(bounds, note_top + offset, text_x,
                        "#{POPUP_BG_DEFAULT}#{' ' * text_width}#{Terminal::ANSI::RESET}")
        end

        wrapped_note = UI::TextUtils.wrap_text(@note, text_width)
        wrapped_note = [''] if wrapped_note.empty?

        cursor_lines = UI::TextUtils.wrap_text(@note[0...@cursor_pos], text_width)
        cursor_line_index = [cursor_lines.length - 1, 0].max

        max_visible_start = [wrapped_note.length - note_rows, 0].max
        visible_start = [cursor_line_index - note_rows + 1, 0].max
        visible_start = [visible_start, max_visible_start].min

        visible_lines = wrapped_note[visible_start, note_rows] || []
        visible_lines += Array.new(note_rows - visible_lines.length, '')

        visible_lines.each_with_index do |line, idx|
          target_row = note_top + idx
          surface.write(bounds, target_row, text_x,
                        "#{POPUP_BG_DEFAULT}#{COLOR_TEXT_PRIMARY}#{UI::TextUtils.pad_right(line, text_width)}#{Terminal::ANSI::RESET}")
        end

        cursor_display_row = cursor_line_index - visible_start
        cursor_display_row = [[cursor_display_row, 0].max, note_rows - 1].min
        cursor_row = note_top + cursor_display_row
        cursor_line = cursor_lines.last || ''
        cursor_col = text_x + [EbookReader::Helpers::TextMetrics.visible_length(cursor_line), text_width - 1].min
        surface.write(bounds, cursor_row, cursor_col,
                      "#{SELECTION_HIGHLIGHT}_#{Terminal::ANSI::RESET}")
      end

      def draw_footer(surface, bounds, geometry)
        cancel_label = 'Cancel'
        save_label = 'Save'
        cancel_width = cancel_label.length + 4
        save_width = save_label.length + 4

        button_row = geometry[:buttons_row]
        footer_bg = "#{POPUP_BG_DEFAULT}#{' ' * geometry[:text_width]}#{Terminal::ANSI::RESET}"
        surface.write(bounds, button_row, geometry[:text_x], footer_bg)

        cancel_col = geometry[:text_x] + geometry[:text_width] - cancel_width
        cancel_col = [cancel_col, geometry[:text_x]].max
        save_col = cancel_col - 2 - save_width
        save_col = [save_col, geometry[:text_x]].max

        draw_button(surface, bounds, button_row, save_col, save_label, SAVE_BUTTON_BG, save_width)
        draw_button(surface, bounds, button_row, cancel_col, cancel_label, CANCEL_BUTTON_BG, cancel_width)

        @button_regions[:save] = { row: button_row, col: save_col, width: save_width }
        @button_regions[:cancel] = { row: button_row, col: cancel_col, width: cancel_width }
      end

      def handle_backspace
        return if @cursor_pos.zero?

        @note.slice!(@cursor_pos - 1)
        @cursor_pos -= 1
      end

      def handle_enter
        insert_newline
      end

      def handle_character(key)
        insert_character(key)
      end

      def insert_newline
        insert_text("\n")
      end

      def insert_character(key)
        return unless printable?(key)

        insert_text(key)
      end

      def insert_text(str)
        @note.insert(@cursor_pos, str)
        @cursor_pos += str.length
      end

      def printable?(key)
        key.is_a?(String) && key.length == 1 && key.ord >= 32
      end

      def save_key?(key)
        SAVE_KEYS.include?(key)
      end

      def cancel_key?(key)
        EbookReader::Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
      end

      def handle_save
        { type: :save, note: @note }
      end

      def handle_click(x, y)
        return nil unless @visible && @button_regions

        @button_regions.each do |key, region|
          next unless y == region[:row]
          next unless x.between?(region[:col], region[:col] + region[:width] - 1)

          return handle_save if key == :save
          return { type: :cancel } if key == :cancel
        end

        nil
      end

      private

      def draw_button(surface, bounds, row, col, label, bg, width)
        reset = Terminal::ANSI::RESET
        text = " #{label} "
        padded = UI::TextUtils.pad_right(text, width)
        surface.write(bounds, row, col, "#{bg}#{BUTTON_FG}#{padded}#{reset}")
      end

      def build_geometry(origin_x, origin_y, width, height)
        inner_x = origin_x + 1
        inner_y = origin_y + 1
        inner_width = width - 2
        inner_height = height - 2
        text_x = inner_x + 1
        text_width = [inner_width - 2, 1].max
        note_rows = [inner_height - 3, 1].max
        {
          box_y: inner_y,
          box_x: inner_x,
          box_height: inner_height,
          box_width: inner_width,
          text_x: text_x,
          text_width: text_width,
          note_rows: note_rows,
          buttons_row: inner_y + inner_height - 2,
        }
      end
    end
  end
end
