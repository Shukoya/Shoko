# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/box_drawer'
require_relative 'ui/overlay_layout'
require_relative 'annotation_editor_overlay/footer_renderer'
require_relative 'annotation_editor_overlay/geometry'
require_relative 'annotation_editor_overlay/note_renderer'
require_relative '../input/key_definitions'
require_relative '../helpers/terminal_sanitizer'

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

      attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

      def initialize(selected_text:, range:, chapter_index:, annotation: nil)
        super()
        @selected_text = (selected_text || '').dup
        @range = range
        @chapter_index = chapter_index
        @annotation_id = annotation.is_a?(Hash) ? (annotation[:id] || annotation['id']) : nil
        note_source = annotation.is_a?(Hash) ? (annotation[:note] || annotation['note']) : nil
        @note = (note_source || '').dup
        @cursor_pos = @note.length
        @visible = true
        @button_regions = {}
        @overlay_sizing = UI::OverlaySizing.new(
          width_ratio: 0.7,
          width_padding: 6,
          min_width: 50,
          height_ratio: 0.6,
          height_padding: 6,
          min_height: 14
        )
      end

      def visible?
        @visible
      end

      def hide
        @visible = false
      end

      def selection_range
        @range
      end

      def render(surface, bounds)
        do_render(surface, bounds)
      end

      def do_render(surface, bounds)
        return unless @visible

        layout = overlay_layout(bounds)

        layout.fill_background(surface, bounds, background: POPUP_BG_DEFAULT)
        draw_box(surface, bounds, layout.origin_y, layout.origin_x, layout.height, layout.width, label: 'Annotation')

        geometry = AnnotationEditorOverlay::Geometry.new(layout)
        note_renderer = AnnotationEditorOverlay::NoteRenderer.new(
          background: POPUP_BG_DEFAULT,
          text_color: COLOR_TEXT_PRIMARY,
          cursor_color: SELECTION_HIGHLIGHT,
          geometry: geometry
        )
        note_renderer.render(surface, bounds, note: @note, cursor_pos: @cursor_pos)

        footer_renderer = AnnotationEditorOverlay::FooterRenderer.new(
          background: POPUP_BG_DEFAULT,
          button_fg: BUTTON_FG,
          save_bg: SAVE_BUTTON_BG,
          cancel_bg: CANCEL_BUTTON_BG
        )
        @button_regions = footer_renderer.render(surface, bounds, geometry)
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
        @overlay_sizing.width_for(total_width)
      end

      def calculate_height(total_height)
        @overlay_sizing.height_for(total_height)
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
        EbookReader::Helpers::TerminalSanitizer.printable_char?(key.to_s)
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

      def handle_click(col, row)
        return nil unless @visible && @button_regions

        @button_regions.each do |key, region|
          next unless row == region[:row]
          next unless col.between?(region[:col], region[:col] + region[:width] - 1)

          return handle_save if key == :save
          return { type: :cancel } if key == :cancel
        end

        nil
      end

      private

      def overlay_layout(bounds)
        width = calculate_width(bounds.width)
        height = calculate_height(bounds.height)
        UI::OverlayLayout.centered(bounds, width: width, height: height)
      end
    end
  end
end
