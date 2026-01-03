# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../helpers/terminal_sanitizer'
require_relative '../ui/box_drawer'
require_relative 'annotation_rendering_helpers'

module EbookReader
  module Components
    module Screens
      # Simple annotation note editor within the menu (no book load)
      class AnnotationEditScreenComponent < BaseComponent
        include Constants::UIConstants
        include UI::BoxDrawer

        attr_reader :edit_state

        # Rendering context for this screen to avoid parameter clumps.
        RenderContext = Struct.new(
          :surface,
          :bounds,
          :width,
          :height,
          :reset,
          :annotation,
          :book_label,
          keyword_init: true
        )

        def initialize(state, dependencies = nil)
          super(dependencies)
          @state = state
          @dependencies = dependencies
          @render_context = nil
          @edit_state = AnnotationEditState.new(@state)
        end

        def do_render(surface, bounds)
          @render_context = build_context(surface, bounds)
          render_header
          render_body
          render_footer
        ensure
          @render_context = nil
        end

        def preferred_height(_available_height)
          :fill
        end

        # --- Unified editor API (used by Application::Commands) ---
        def save_annotation
          payload = edit_state.annotation_update_payload
          return unless payload

          persist_annotation(payload)
          edit_state.return_to_annotations_list
        end

        def handle_backspace
          edit_state.update_from do |text, cursor|
            next nil if cursor <= 0

            prev_cursor = cursor - 1
            [text[0...prev_cursor] + text[(prev_cursor + 1)..].to_s, prev_cursor]
          end
        end

        def handle_enter
          edit_state.update_from do |text, cursor|
            new_text = text.dup
            new_text.insert(cursor, "\n")
            [new_text, cursor + 1]
          end
        end

        def handle_character(char)
          return unless EbookReader::Helpers::TerminalSanitizer.printable_char?(char.to_s)

          edit_state.update_from do |text, cursor|
            new_text = text.dup
            new_text.insert(cursor, char)
            [new_text, cursor + 1]
          end
        end

        private

        def build_context(surface, bounds)
          annotation = edit_state.selected_annotation
          RenderContext.new(
            surface: surface,
            bounds: bounds,
            width: bounds.width,
            height: bounds.height,
            reset: Terminal::ANSI::RESET,
            annotation: AnnotationView.new(annotation || {}),
            book_label: resolve_book_label
          )
        end

        def resolve_book_label
          book_path = @state.get(%i[menu selected_annotation_book])
          return 'Unknown Book' unless book_path

          raw = File.basename(book_path)
          EbookReader::Helpers::TerminalSanitizer.sanitize(
            raw,
            preserve_newlines: false,
            preserve_tabs: false
          )
        end

        def render_header
          title_width = render_title
          render_hint(title_width)
          render_divider
        end

        def render_title
          title_plain = "📝 Edit Annotation • #{context.book_label}"
          title_width = EbookReader::Helpers::TextMetrics.visible_length(title_plain)
          title = "#{COLOR_TEXT_ACCENT}#{title_plain}#{context.reset}"
          context.surface.write(context.bounds, 1, 2, title)
          title_width
        end

        def render_hint(title_width)
          hint_plain = '[Ctrl+S] Save • [ESC] Cancel'
          hint_col = hint_column(title_width, hint_plain)
          context.surface.write(
            context.bounds,
            1,
            hint_col,
            "#{COLOR_TEXT_DIM}#{hint_plain}#{context.reset}"
          )
        end

        def render_divider
          context.surface.write(
            context.bounds,
            2,
            1,
            COLOR_TEXT_DIM + ('─' * context.width) + context.reset
          )
        end

        def hint_column(title_width, hint_plain)
          hint_width = EbookReader::Helpers::TextMetrics.visible_length(hint_plain)
          min_hint_col = 2 + title_width + 2
          right_hint_col = context.width - hint_width
          [right_hint_col, min_hint_col].max
        end

        def render_body
          text_box = snippet_box
          render_text_box(text_box)
          render_note_box(note_box(text_box))
        end

        def render_footer
          context.surface.write(
            context.bounds,
            context.height - 1,
            2,
            "#{COLOR_TEXT_DIM}[Type] to edit • [Backspace] delete • [Enter] newline#{context.reset}"
          )
        end

        def snippet_box
          AnnotationTextBox.new(
            row: 4,
            height: [context.height * 0.25, 6].max.to_i,
            width: context.width - 4,
            label: 'Selected Text',
            text: context.annotation.text
          )
        end

        def note_box(text_box)
          text_box.next_box(
            total_height: context.height,
            label: 'Note (editable)',
            text: edit_state.text
          )
        end

        def render_text_box(box)
          box.render(context, drawer: self, color_prefix: COLOR_TEXT_PRIMARY)
        end

        def render_note_box(box)
          render_text_box(box)
          render_cursor(box)
        end

        def render_cursor(box)
          cursor = edit_state.cursor(box.text)
          row, col = box.cursor_position(cursor)
          context.surface.write(context.bounds, row, col, "#{SELECTION_HIGHLIGHT}_#{context.reset}")
        end

        def persist_annotation(payload)
          service = @dependencies&.resolve(:annotation_service)
          return unless service

          path, ann_id, text = payload.values_at(:path, :ann_id, :text)
          service.update(path, ann_id, text)
          edit_state.refresh_annotations(service)
        rescue StandardError
          nil
        end

        def context
          @render_context
        end
      end
    end
  end
end
