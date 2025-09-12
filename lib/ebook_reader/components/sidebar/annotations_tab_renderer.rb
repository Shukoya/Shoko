# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # Annotations tab renderer for sidebar
      class AnnotationsTabRenderer < BaseComponent
        include Constants::UIConstants

        ItemCtx = Struct.new(:annotation, :index, :selected_index, :y, keyword_init: true)

        def initialize(controller)
          super()
          @controller = controller
        end

        def do_render(surface, bounds)
          state = @controller.state
          annotations = state.get(%i[reader annotations]) || []
          selected_index = state.get(%i[reader sidebar_annotations_selected]) || 0

          return render_empty_message(surface, bounds) if annotations.empty?

          render_annotations_list(surface, bounds, annotations, selected_index)
        end

        private

      def render_empty_message(surface, bounds)
          reset = Terminal::ANSI::RESET
          bx = bounds.x
          by = bounds.y
          bw = bounds.width
          bh = bounds.height
          messages = [
            'No annotations yet',
            '',
            'Select text while reading',
            'to create annotations',
          ]

          start_y = by + ((bh - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bx + [(bw - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{reset}")
          end
      end

        def render_annotations_list(surface, bounds, annotations, selected_index)
          # Each annotation takes 3 lines: text excerpt, note (if any), location
          item_height = 3
          bh = bounds.height
          by = bounds.y
          visible_items = bh / item_height

          # Calculate scrolling
          visible_start = [selected_index - (visible_items / 2), 0].max
          visible_end = [visible_start + visible_items, annotations.length].min

          current_y = by

          (visible_start...visible_end).each do |idx|
            annotation = annotations[idx]
            break if current_y + item_height > by + bh

            ctx = ItemCtx.new(annotation: annotation, index: idx, selected_index: selected_index, y: current_y)
            render_annotation_item(surface, bounds, ctx)
            current_y += item_height
          end
        end

        def render_annotation_item(surface, bounds, ctx)
          is_selected = (ctx.index == ctx.selected_index)
          bx = bounds.x
          by = bounds.y
          bw = bounds.width
          max_width = bw - 4

          # Color indicator based on highlight color
          ann = ctx.annotation
          color_indicator = get_color_indicator(ann['color'])

          # Text excerpt (first line)
          text = ann['text'] || ''
          excerpt = text.tr("\n", ' ').strip
          excerpt = "#{excerpt[0, max_width - 6]}..." if excerpt.length > max_width - 3

          reset = Terminal::ANSI::RESET
          if is_selected
            prefix = "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}"
            note_style = COLOR_TEXT_PRIMARY
            location_style = COLOR_TEXT_SECONDARY
          else
            prefix = '  '
            note_style = COLOR_TEXT_DIM
            location_style = COLOR_TEXT_DIM
          end
          text_line = "#{prefix}#{color_indicator}#{excerpt}#{reset}"
          row = ctx.y
          col1 = bx + 1
          surface.write(bounds, row, col1, text_line)

          # Note (second line, if exists)
          note = ann['note']
          if note && !note.strip.empty?
            note_text = note.tr("\n", ' ').strip
            note_text = "#{note_text[0, max_width - 5]}..." if note_text.length > max_width - 2

            note_line = "  #{Terminal::ANSI::ITALIC}#{note_style}✎ #{note_text}#{reset}"
            surface.write(bounds, row + 1, col1, note_line)
          end

          # Location (third line)
          location = format_location(ann)
          location_line = "  #{location_style}#{location}#{reset}"
          surface.write(bounds, row + 2, col1, location_line)
        end

        def get_color_indicator(color)
          reset = Terminal::ANSI::RESET
          case color&.downcase
          when 'yellow', 'highlight'
            "#{COLOR_TEXT_WARNING}●#{reset} "
          when 'red'
            "#{COLOR_TEXT_ERROR}●#{reset} "
          when 'green'
            "#{COLOR_TEXT_SUCCESS}●#{reset} "
          when 'blue'
            "#{COLOR_TEXT_ACCENT}●#{reset} "
          else
            "#{COLOR_TEXT_PRIMARY}●#{reset} "
          end
        end

        def format_location(annotation)
          ch_idx = annotation['chapter_index'] || 0
          chapter_title = annotation['chapter_title'] || "Ch. #{ch_idx + 1}"

          # Try to calculate percentage if we have position info
          percentage = ''
          start_pos = annotation['start_position']
          ch_len = annotation['chapter_length']
          if start_pos && ch_len
            pct = (start_pos.to_f / ch_len * 100).round
            percentage = " · #{pct}%"
          end

          "#{chapter_title}#{percentage}"
        end
      end
    end
  end
end
