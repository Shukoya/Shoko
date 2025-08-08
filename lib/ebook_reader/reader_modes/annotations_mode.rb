# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # Mode for viewing all annotations
    class AnnotationsMode < BaseMode
      include Concerns::InputHandler

      def initialize(reader)
        super
        @selected = 0
        load_annotations
      end

      def draw(height, width)
        draw_header(width)

        if @annotations.empty?
          draw_empty_state(height, width)
        else
          draw_annotations_list(height, width)
        end

        draw_footer(height)
      end

      def handle_input(key)
        return handle_empty_input(key) if @annotations.empty?

        case key
        when "\e", 'A' then reader.switch_mode(:read)
        when "\r", "\n" then edit_annotation
        when 'd', 'D' then delete_annotation
        else handle_navigation(key)
        end
      end

      private

      def load_annotations
        path = reader.instance_variable_get(:@path)
        @annotations = Annotations::AnnotationStore.get(path)
      end

      def draw_header(width)
        terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📝 Annotations#{Terminal::ANSI::RESET}")
        terminal.write(1, [width - 40, 40].max,
                       "#{Terminal::ANSI::DIM}[A/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")
      end

      def draw_empty_state(height, width)
        terminal.write(height / 2, (width - 25) / 2,
                       "#{Terminal::ANSI::DIM}No annotations yet#{Terminal::ANSI::RESET}")
        terminal.write((height / 2) + 2, (width - 35) / 2,
                       "#{Terminal::ANSI::DIM}Select text to create one#{Terminal::ANSI::RESET}")
      end

      def draw_annotations_list(height, width)
        list_start = 4
        list_height = (height - 6) / 3

        visible_range = calculate_visible_range(list_height)

        visible_range.each_with_index do |idx, row_idx|
          annotation = @annotations[idx]
          draw_annotation_item(annotation, idx, list_start + (row_idx * 3), width)
        end
      end

      def draw_annotation_item(annotation, idx, row, width)
        is_selected = idx == @selected

        # Selection indicator
        if is_selected
          terminal.write(row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
        else
          terminal.write(row, 2, '  ')
        end

        # Quoted text
        text = annotation['text'].tr("\n", ' ').strip[0, width - 10]
        terminal.write(row, 4,
                       "#{Terminal::ANSI::DIM}\"#{text}\"#{Terminal::ANSI::RESET}")

        # Note
        note = annotation['note'].tr("\n", ' ').strip[0, width - 10]
        color = is_selected ? Terminal::ANSI::BRIGHT_WHITE : Terminal::ANSI::WHITE
        terminal.write(row + 1, 6, color + note + Terminal::ANSI::RESET)

        # Timestamp
        time = Time.parse(annotation['created_at']).strftime('%Y-%m-%d %H:%M')
        terminal.write(row + 2, 6,
                       Terminal::ANSI::DIM + Terminal::ANSI::GRAY + time + Terminal::ANSI::RESET)
      end

      def draw_footer(height)
        terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Edit • d Delete • A/ESC Back#{Terminal::ANSI::RESET}")
      end

      def calculate_visible_range(items_per_page)
        visible_start = [@selected - (items_per_page / 2), 0].max
        visible_end = [visible_start + items_per_page, @annotations.length].min
        visible_start...visible_end
      end

      def handle_empty_input(key)
        reader.switch_mode(:read) if ["\e", 'A'].include?(key)
      end

      def handle_navigation(key)
        @selected = handle_navigation_keys(key, @selected, @annotations.length - 1)
      end

      def edit_annotation
        annotation = @annotations[@selected]
        return unless annotation

        reader.switch_mode(:annotation_editor, annotation: annotation)
      end

      def delete_annotation
        annotation = @annotations[@selected]
        return unless annotation

        path = reader.instance_variable_get(:@path)
        Annotations::AnnotationStore.delete(path, annotation['id'])
        load_annotations
        @selected = [@selected, @annotations.length - 1].min if @annotations.any?
        reader.refresh_annotations if reader.respond_to?(:refresh_annotations)
        reader.send(:set_message, 'Annotation deleted!')
      end
    end
  end
end
