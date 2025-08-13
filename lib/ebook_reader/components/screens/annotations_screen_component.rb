# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Annotations screen component for viewing and managing annotations
      class AnnotationsScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(state)
          super()
          @state = state
          @selected = 0
          @annotations_by_book = {}
          @current_book_path = nil
          @current_annotation = nil
          refresh_data
        end

        def selected
          @selected
        end

        def selected=(value)
          @selected = [value, 0].max
          update_current_annotation
        end

        def current_annotation
          @current_annotation
        end

        def current_book_path
          @current_book_path
        end

        def navigate(direction)
          annotations = current_annotations
          return if annotations.empty?

          case direction
          when :up
            @selected = [@selected - 1, 0].max
          when :down
            @selected = [@selected + 1, annotations.length - 1].min
          end
          
          update_current_annotation
        end

        def refresh_data
          # Load annotations from store - would need to implement proper loading
          @annotations_by_book = {}
          
          # For now, use empty state - this would be populated from actual annotation store
          @selected = 0
          update_current_annotation
        end

        def do_render(surface, bounds)
          height = bounds.height
          width = bounds.width

          # Header
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}📝 Annotations#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, width - 20, "#{COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}")

          annotations = current_annotations
          
          if annotations.empty?
            render_empty_state(surface, bounds, width, height)
          else
            render_annotations_list(surface, bounds, width, height, annotations)
          end

          # Footer instructions
          if annotations.any?
            surface.write(bounds, height - 3, 2, "#{COLOR_TEXT_DIM}[Enter] Edit • [d] Delete#{Terminal::ANSI::RESET}")
          end
          surface.write(bounds, height - 2, 2, "#{COLOR_TEXT_DIM}[ESC] Back to menu#{Terminal::ANSI::RESET}")
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def current_annotations
          return [] unless @current_book_path
          @annotations_by_book[@current_book_path] || []
        end

        def update_current_annotation
          annotations = current_annotations
          @current_annotation = annotations[@selected] if @selected < annotations.length
        end

        def render_empty_state(surface, bounds, width, height)
          empty_text = "#{COLOR_TEXT_DIM}No annotations found#{Terminal::ANSI::RESET}"
          surface.write(bounds, height / 2, [(width - empty_text.length + 10) / 2, 1].max, empty_text)
          
          help_text = "#{COLOR_TEXT_DIM}Annotations you create while reading will appear here#{Terminal::ANSI::RESET}"
          surface.write(bounds, height / 2 + 2, [(width - help_text.length + 10) / 2, 1].max, help_text)
        end

        def render_annotations_list(surface, bounds, width, height, annotations)
          list_start_row = 3
          list_height = height - list_start_row - 4
          return if list_height <= 0

          start_index, visible_annotations = calculate_visible_range(list_height, annotations)

          visible_annotations.each_with_index do |annotation, index|
            row = list_start_row + index
            is_selected = (start_index + index) == @selected

            render_annotation_item(surface, bounds, row, width, annotation, is_selected)
          end
        end

        def calculate_visible_range(list_height, annotations)
          total_annotations = annotations.length
          start_index = 0

          if @selected >= list_height
            start_index = @selected - list_height + 1
          end

          if total_annotations > list_height
            start_index = [start_index, total_annotations - list_height].min
          end

          end_index = [start_index + list_height - 1, total_annotations - 1].min
          visible_annotations = annotations[start_index..end_index] || []

          [start_index, visible_annotations]
        end

        def render_annotation_item(surface, bounds, row, width, annotation, is_selected)
          # Extract annotation details
          text = annotation[:text] || 'No text'
          note = annotation[:note] || ''
          book_title = annotation[:book_title] || 'Unknown Book'
          
          # Truncate for display
          max_text_length = [width - 20, 40].max
          display_text = truncate_text(text, max_text_length)
          
          prefix = is_selected ? '▶ ' : '  '
          content = "#{prefix}\"#{display_text}\""
          content += " #{COLOR_TEXT_DIM}(#{truncate_text(note, 20)})#{Terminal::ANSI::RESET}" unless note.empty?

          if is_selected
            surface.write(bounds, row, 1, SELECTION_HIGHLIGHT + content + Terminal::ANSI::RESET)
          else
            surface.write(bounds, row, 1, COLOR_TEXT_PRIMARY + content + Terminal::ANSI::RESET)
          end
        end

        def truncate_text(text, max_length)
          return text if text.length <= max_length
          "#{text[0...max_length - 3]}..."
        end
      end
    end
  end
end