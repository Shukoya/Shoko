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
          @list = []
          @mode = :book
          @current_book_path = nil
          @current_annotation = nil
          refresh_data
        end

        attr_reader :selected, :current_annotation, :current_book_path

        def selected=(value)
          @selected = [value, 0].max
          update_current_annotation
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

        # Normalize raw annotations (string-keyed hashes) into symbol-keyed items
        # Includes page metadata when present
        # (duplicate normalize_list method removed)

        def refresh_data
          prev_selected = @selected
          path = @state.get(%i[reader book_path])
          if path && !path.to_s.empty?
            @mode = :book
            @current_book_path = path
            raw = @state.get(%i[reader annotations]) || []
            @list = normalize_list(raw).map { |a| a.merge(book_path: path) }
          else
            @mode = :all
            mapping = @state.get(%i[menu annotations_all]) || {}
            flattened = []
            mapping.each do |book_path, items|
              normalize_list(items).each do |a|
                flattened << a.merge(book_path: book_path)
              end
            end
            @list = flattened
          end

          annotations = current_annotations
          @selected = [[prev_selected, 0].max, [annotations.length - 1, 0].max].min
          update_current_annotation
        end

        def do_render(surface, bounds)
          # Ensure data is fresh each render
          refresh_data
          height = bounds.height
          width = bounds.width

          # Header
          count = current_annotations.length
          book_label = if @mode == :all
                         'All Books'
                       else
                         (@current_book_path ? File.basename(@current_book_path) : 'No book selected')
                       end
          header_left = "#{COLOR_TEXT_ACCENT}📝 Annotations (#{count}) — #{book_label}#{Terminal::ANSI::RESET}"
          header_right = "#{COLOR_TEXT_DIM}[Enter] Open • [e] Edit • [d] Delete#{Terminal::ANSI::RESET}"
          surface.write(bounds, 1, 2, header_left)
          surface.write(bounds, 1, [width - header_right.length - 1, header_left.length + 2].max,
                        header_right)
          # Divider and column headers
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + Terminal::ANSI::RESET)
          idx_w = 4
          ch_w = 6
          date_w = 10
          book_w = (@mode == :all ? 12 : 0)
          avail = width - (idx_w + ch_w + date_w + book_w + 8)
          snippet_w = (avail * 0.55).to_i
          note_w = avail - snippet_w
          columns = if @mode == :all
                      format("%-#{idx_w}s  %-#{ch_w}s  %-#{snippet_w}s  %-#{note_w}s  %-#{book_w}s  %-#{date_w}s",
                             '#', 'Ch', 'Snippet', 'Note', 'Book', 'Date')
                    else
                      format("%-#{idx_w}s  %-#{ch_w}s  %-#{snippet_w}s  %-#{note_w}s  %-#{date_w}s",
                             '#', 'Ch', 'Snippet', 'Note', 'Date')
                    end
          surface.write(bounds, 3, 1, COLOR_TEXT_DIM + columns + Terminal::ANSI::RESET)

          annotations = current_annotations

          if annotations.empty?
            render_empty_state(surface, bounds, width, height)
          else
            render_annotations_list(surface, bounds, width, height, annotations)
          end

          # Footer instructions
          surface.write(bounds, height - 2, 2,
                        "#{COLOR_TEXT_DIM}[↑/↓] Navigate • [Enter] Open • [d] Delete • [ESC] Back#{Terminal::ANSI::RESET}")
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def current_annotations
          @list || []
        end

        def update_current_annotation
          annotations = current_annotations
          @current_annotation = annotations[@selected] if @selected < annotations.length
          return unless @current_annotation && @current_annotation[:book_path]

          @current_book_path = @current_annotation[:book_path]
        end

        def render_empty_state(surface, bounds, width, height)
          empty_text = "#{COLOR_TEXT_DIM}No annotations found#{Terminal::ANSI::RESET}"
          surface.write(bounds, height / 2, [(width - empty_text.length + 10) / 2, 1].max,
                        empty_text)

          help_text = "#{COLOR_TEXT_DIM}Annotations you create while reading will appear here#{Terminal::ANSI::RESET}"
          surface.write(bounds, (height / 2) + 2, [(width - help_text.length + 10) / 2, 1].max,
                        help_text)
        end

        def render_annotations_list(surface, bounds, width, height, annotations)
          list_start_row = 4
          list_height = height - list_start_row - 2
          return if list_height <= 0

          start_index, visible_annotations = calculate_visible_range(list_height, annotations)

          visible_annotations.each_with_index do |annotation, index|
            row = list_start_row + index
            is_selected = (start_index + index) == @selected

            render_annotation_item(surface, bounds, row, width, annotation, is_selected, (start_index + index))
          end
        end

        def calculate_visible_range(list_height, annotations)
          total_annotations = annotations.length
          start_index = 0

          start_index = @selected - list_height + 1 if @selected >= list_height

          if total_annotations > list_height
            start_index = [start_index, total_annotations - list_height].min
          end

          end_index = [start_index + list_height - 1, total_annotations - 1].min
          visible_annotations = annotations[start_index..end_index] || []

          [start_index, visible_annotations]
        end

        def render_annotation_item(surface, bounds, row, width, annotation, is_selected, absolute_index)
          # Extract annotation details
          text = (annotation[:text] || 'No text').to_s.tr("\n", ' ')
          note = (annotation[:note] || '').to_s.tr("\n", ' ')
          created = (annotation[:created_at] || '').to_s.split('T').first
          chapter = annotation[:chapter_index]

          # Column widths (match header)
          idx_w = 4
          ch_w = 6
          date_w = 10
          book_w = (@mode == :all ? 12 : 0)
          avail = width - (idx_w + ch_w + date_w + book_w + 8)
          snippet_w = (avail * 0.6).to_i
          note_w = avail - snippet_w

          pointer = is_selected ? '▸' : ' '
          idx = format("%#{idx_w}d", absolute_index + 1)
          chv = chapter.nil? ? '-' : chapter.to_i
          snippet = truncate_text(text, snippet_w)
          note_tr = truncate_text(note, note_w)
          if @mode == :all
            book = annotation[:book_path] ? File.basename(annotation[:book_path]) : ''
            line = format("%s %s  %-#{ch_w}s  %-#{snippet_w}s  %-#{note_w}s  %-#{book_w}s  %-#{date_w}s",
                          pointer, idx, chv, snippet, note_tr, truncate_text(book, book_w), created)
          else
            line = format("%s %s  %-#{ch_w}s  %-#{snippet_w}s  %-#{note_w}s  %-#{date_w}s",
                          pointer, idx, chv, snippet, note_tr, created)
          end

          color = is_selected ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
          surface.write(bounds, row, 1, color + line + Terminal::ANSI::RESET)
        end

        def truncate_text(text, max_length)
          return text if text.length <= max_length

          "#{text[0...(max_length - 3)]}..."
        end

        def normalize_list(raw)
          (raw || []).map do |a|
            {
              text: a['text'],
              note: a['note'],
              id: a['id'],
              range: a['range'],
              chapter_index: a['chapter_index'],
              created_at: a['created_at'],
              updated_at: a['updated_at'],
              page_current: a['page_current'],
              page_total: a['page_total'],
              page_mode: a['page_mode'],
            }
          end
        end
      end
    end
  end
end
