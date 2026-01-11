# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../../../terminal/text_metrics.rb'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Normalized view of annotation data for screen rendering.
      class AnnotationView
        def initialize(annotation)
          @annotation = annotation.is_a?(Hash) ? annotation : {}
        end

        def text
          fetch(:text).to_s
        end

        def note
          fetch(:note).to_s
        end

        def chapter_index
          fetch(:chapter_index)
        end

        def id
          fetch(:id)
        end

        def formatted_date
          created = fetch(:created_at)
          created.to_s.tr('T', ' ').sub('Z', '')
        end

        def page_meta
          curr = fetch(:page_current)
          total = fetch(:page_total)
          return nil unless curr && total

          mode = fetch(:page_mode).to_s
          label = mode.empty? ? '' : "#{mode}: "
          "#{label}#{curr}/#{total}"
        end

        private

        def fetch(key)
          @annotation[key] || @annotation[key.to_s]
        end
      end

      # Text box helper for annotation screens.
      class AnnotationTextBox
        BOX_COLUMN = 2
        TEXT_COLUMN = 4
        BOX_SPACING = 2
        MIN_HEIGHT = 6
        BOTTOM_PADDING = 3

        attr_reader :row, :height, :width, :label, :text

        def initialize(row:, height:, width:, label:, text:)
          @row = row
          @height = height
          @width = width
          @label = label
          @text = text.to_s
        end

        def inner_width
          width - 4
        end

        def frame_args
          {
            row: row,
            height: height,
            width: width,
            label: label,
          }
        end

        def each_visible_line(&block)
          return enum_for(__method__) unless block

          lines = UI::TextUtils.wrap_text(text, inner_width)
          lines.first(max_lines).each_with_index(&block)
        end

        def render(context, drawer:, color_prefix:)
          drawer.draw_box(
            context.surface,
            context.bounds,
            row,
            BOX_COLUMN,
            height,
            width,
            label: label
          )
          render_lines(context, color_prefix: color_prefix)
        end

        def render_lines(context, color_prefix:)
          each_visible_line do |line, index|
            padded = UI::TextUtils.pad_right(line, inner_width)
            context.surface.write(
              context.bounds,
              row + 1 + index,
              TEXT_COLUMN,
              "#{color_prefix}#{padded}#{context.reset}"
            )
          end
        end

        def cursor_position(cursor)
          cursor_lines = UI::TextUtils.wrap_text(text[0, cursor], inner_width)
          cursor_row = row + 1 + [cursor_lines.length - 1, 0].max
          cursor_col = TEXT_COLUMN + Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(cursor_lines.last || '')
          [cursor_row, cursor_col]
        end

        def next_box(total_height:, label:, text:)
          next_row = row + height + BOX_SPACING
          next_height = [total_height - next_row - BOTTOM_PADDING, MIN_HEIGHT].max
          AnnotationTextBox.new(row: next_row, height: next_height, width: width, label: label, text: text)
        end

        private

        def max_lines
          [height - 2, 0].max
        end
      end

      # Menu-state helper for annotation edit screens.
      class AnnotationEditState
        def initialize(state)
          @state = state
        end

        def text
          (@state.get(%i[menu annotation_edit_text]) || '').to_s
        end

        def cursor(text = self.text)
          (@state.get(%i[menu annotation_edit_cursor]) || text.length).to_i
        end

        def update_from
          current_text = text
          current_cursor = cursor(current_text)
          updated = yield(current_text, current_cursor)
          update(text: updated[0], cursor: updated[1]) if updated
        end

        def update(text:, cursor:)
          @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(
                            annotation_edit_text: text,
                            annotation_edit_cursor: cursor
                          ))
        end

        def selected_annotation
          ann = @state.get(%i[menu selected_annotation])
          ann if ann.is_a?(Hash)
        end

        def annotation_update_payload
          annotation = selected_annotation || {}
          path = @state.get(%i[menu selected_annotation_book])
          ann_id = annotation[:id] || annotation['id']
          return nil unless path && ann_id

          { path: path, ann_id: ann_id, text: text }
        end

        def refresh_annotations(service)
          @state.dispatch(
            Shoko::Application::Actions::UpdateMenuAction.new(annotations_all: service.list_all)
          )
        end

        def return_to_annotations_list
          @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(mode: :annotations))
        end
      end
    end
  end
end
