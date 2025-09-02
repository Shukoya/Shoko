# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # Annotations tab renderer for sidebar
      class AnnotationsTabRenderer < BaseComponent
        include Constants::UIConstants
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
          messages = [
            'No annotations yet',
            '',
            'Select text while reading',
            'to create annotations',
          ]

          start_y = bounds.y + ((bounds.height - messages.length) / 2)
          messages.each_with_index do |message, i|
            x = bounds.x + [(bounds.width - message.length) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}")
          end
        end

        def render_annotations_list(surface, bounds, annotations, selected_index)
          # Each annotation takes 3 lines: text excerpt, note (if any), location
          item_height = 3
          visible_items = bounds.height / item_height

          # Calculate scrolling
          visible_start = [selected_index - (visible_items / 2), 0].max
          visible_end = [visible_start + visible_items, annotations.length].min

          current_y = bounds.y

          (visible_start...visible_end).each do |idx|
            annotation = annotations[idx]
            break if current_y + item_height > bounds.y + bounds.height

            render_annotation_item(surface, bounds, annotation, idx, selected_index, current_y)
            current_y += item_height
          end
        end

        def render_annotation_item(surface, bounds, annotation, idx, selected_index, y)
          is_selected = (idx == selected_index)
          max_width = bounds.width - 4

          # Color indicator based on highlight color
          color_indicator = get_color_indicator(annotation['color'])

          # Text excerpt (first line)
          text = annotation['text'] || ''
          excerpt = text.tr("\n", ' ').strip
          excerpt = "#{excerpt[0, max_width - 6]}..." if excerpt.length > max_width - 3

          prefix = is_selected ? "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{Terminal::ANSI::RESET}" : '  '
          text_line = "#{prefix}#{color_indicator}#{excerpt}#{Terminal::ANSI::RESET}"

          surface.write(bounds, y, bounds.x + 1, text_line)

          # Note (second line, if exists)
          note = annotation['note']
          if note && !note.strip.empty?
            note_text = note.tr("\n", ' ').strip
            note_text = "#{note_text[0, max_width - 5]}..." if note_text.length > max_width - 2

            note_style = is_selected ? COLOR_TEXT_PRIMARY : COLOR_TEXT_DIM
            note_line = "  #{Terminal::ANSI::ITALIC}#{note_style}✎ #{note_text}#{Terminal::ANSI::RESET}"
            surface.write(bounds, y + 1, bounds.x + 1, note_line)
          end

          # Location (third line)
          location = format_location(annotation)
          location_style = is_selected ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DIM
          location_line = "  #{location_style}#{location}#{Terminal::ANSI::RESET}"
          surface.write(bounds, y + 2, bounds.x + 1, location_line)
        end

        def get_color_indicator(color)
          case color&.downcase
          when 'yellow', 'highlight'
            "#{COLOR_TEXT_WARNING}●#{Terminal::ANSI::RESET} "
          when 'red'
            "#{COLOR_TEXT_ERROR}●#{Terminal::ANSI::RESET} "
          when 'green'
            "#{COLOR_TEXT_SUCCESS}●#{Terminal::ANSI::RESET} "
          when 'blue'
            "#{COLOR_TEXT_ACCENT}●#{Terminal::ANSI::RESET} "
          else
            "#{COLOR_TEXT_PRIMARY}●#{Terminal::ANSI::RESET} "
          end
        end

        def format_location(annotation)
          chapter_index = annotation['chapter_index'] || 0
          chapter_title = annotation['chapter_title'] || "Ch. #{chapter_index + 1}"

          # Try to calculate percentage if we have position info
          percentage = ''
          if annotation['start_position'] && annotation['chapter_length']
            pct = (annotation['start_position'].to_f / annotation['chapter_length'] * 100).round
            percentage = " · #{pct}%"
          end

          "#{chapter_title}#{percentage}"
        end
      end
    end
  end
end
