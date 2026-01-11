# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/terminal_sanitizer.rb'
require_relative '../ui/box_drawer'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Detailed view for a single annotation selected from the list
      class AnnotationDetailScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI
        include UI::BoxDrawer

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

        def initialize(state)
          super()
          @state = state
          @render_context = nil
        end

        def do_render(surface, bounds)
          @render_context = build_context(surface, bounds)
          render_header
          return render_empty(context.surface, context.bounds) unless context.annotation

          render_body
        ensure
          @render_context = nil
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def build_context(surface, bounds)
          annotation = selected_annotation
          RenderContext.new(
            surface: surface,
            bounds: bounds,
            width: bounds.width,
            height: bounds.height,
            reset: Terminal::ANSI::RESET,
            annotation: annotation ? AnnotationView.new(annotation) : nil,
            book_label: resolve_book_label
          )
        end

        def resolve_book_label
          book_path = @state.get(%i[menu selected_annotation_book])
          return 'Unknown Book' unless book_path

          raw = File.basename(book_path)
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(
            raw,
            preserve_newlines: false,
            preserve_tabs: false
          )
        end

        def render_header
          title_width = render_title
          render_actions(title_width)
          render_divider
        end

        def render_title
          title_plain = "📝 Annotation • #{context.book_label}"
          title_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(title_plain)
          title = "#{COLOR_TEXT_ACCENT}#{title_plain}#{context.reset}"
          context.surface.write(context.bounds, 1, 2, title)
          title_width
        end

        def render_actions(title_width)
          actions_plain = '[o] Open • [e] Edit • [d] Delete • [ESC] Back'
          actions_col = actions_column(title_width, actions_plain)
          context.surface.write(
            context.bounds,
            1,
            actions_col,
            "#{COLOR_TEXT_DIM}#{actions_plain}#{context.reset}"
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

        def actions_column(title_width, actions_plain)
          actions_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(actions_plain)
          min_actions_col = 2 + title_width + 2
          right_actions_col = context.width - actions_width
          [right_actions_col, min_actions_col].max
        end

        def render_metadata
          annotation = context.annotation
          page_meta = annotation.page_meta
          meta_line = [
            "Ch: #{annotation.chapter_index || '-'}",
            page_meta && "Page: #{page_meta}",
            "Saved: #{annotation.formatted_date}",
          ].compact.join('   ')
          context.surface.write(
            context.bounds,
            3,
            2,
            COLOR_TEXT_DIM + meta_line + context.reset
          )
        end

        def render_body
          render_metadata
          text_box = selected_text_box
          render_text_box(text_box)
          render_text_box(note_box(text_box))
        end

        def selected_text_box
          AnnotationTextBox.new(
            row: 5,
            height: [context.height * 0.35, 8].max.to_i,
            width: context.width - 4,
            label: 'Selected Text',
            text: context.annotation.text
          )
        end

        def note_box(text_box)
          text_box.next_box(
            total_height: context.height,
            label: 'Note',
            text: context.annotation.note
          )
        end

        def render_text_box(box)
          box.render(context, drawer: self, color_prefix: COLOR_TEXT_PRIMARY)
        end

        def context
          @render_context
        end

        def selected_annotation
          ann = @state.get(%i[menu selected_annotation])
          ann if ann.is_a?(Hash)
        end

        # draw_box and wrap_text are provided by included UI modules
      end
    end
  end
end
