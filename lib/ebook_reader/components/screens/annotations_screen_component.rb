# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module EbookReader
  module Components
    module Screens
      # Annotations screen component for viewing and managing annotations
      class AnnotationsScreenComponent < BaseComponent
        include Constants::UIConstants
        include UI::TextUtils

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
          upper = [annotations.length - 1, 0].max
          @selected = prev_selected.clamp(0, upper)
          update_current_annotation
        end

        def do_render(surface, bounds)
          # Ensure data is fresh each render
          refresh_data
          height = bounds.height
          width = bounds.width

          # Header
          reset = Terminal::ANSI::RESET
          count = current_annotations.length
          all_mode = (@mode == :all)
          book_label = if @current_book_path
                         File.basename(@current_book_path)
                       else
                         (all_mode ? 'All Books' : 'No book selected')
                       end
          header_left_plain = "📝 Annotations (#{count}) — #{book_label}"
          header_left = "#{COLOR_TEXT_ACCENT}#{header_left_plain}#{reset}"

          header_right_plain = '[Enter] Open • [e] Edit • [d] Delete'
          header_right = "#{COLOR_TEXT_DIM}#{header_right_plain}#{reset}"

          surface.write(bounds, 1, 2, header_left)
          header_right_width = EbookReader::Helpers::TextMetrics.visible_length(header_right_plain)
          header_left_width = EbookReader::Helpers::TextMetrics.visible_length(header_left_plain)
          min_right_col = 2 + header_left_width + 2
          right_aligned_col = width - header_right_width - 1
          right_col = [right_aligned_col, min_right_col].max
          surface.write(bounds, 1, right_col, header_right)
          # Divider and column headers
          surface.write(bounds, 2, 1, COLOR_TEXT_DIM + ('─' * width) + reset)
          idx_w = 4
          ch_w = 6
          date_w = 10
          book_w = all_mode ? 12 : 0
          avail = width - (idx_w + ch_w + date_w + book_w + 8)
          snippet_w = (avail * 0.55).to_i
          note_w = avail - snippet_w
          has_book_col = book_w.positive?
          columns = [
            '  ',
            pad_right('#', idx_w),
            '  ',
            pad_right('Ch', ch_w),
            '  ',
            pad_right('Snippet', snippet_w),
            '  ',
            pad_right('Note', note_w),
            (has_book_col ? "  #{pad_right('Book', book_w)}" : ''),
            '  ',
            pad_right('Date', date_w),
          ].join
          surface.write(bounds, 3, 1, COLOR_TEXT_DIM + columns + reset)

          annotations = current_annotations

          if annotations.empty?
            render_empty_state(surface, bounds, width, height)
          else
            render_annotations_list(surface, bounds, width, height, annotations, has_book_col)
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
          return unless @current_annotation

          book_path = @current_annotation[:book_path]
          return unless book_path

          @current_book_path = book_path
        end

        def render_empty_state(surface, bounds, width, height)
          reset = Terminal::ANSI::RESET
          empty_text = "#{COLOR_TEXT_DIM}No annotations found#{reset}"
          mid = height / 2
          surface.write(bounds, mid,
                        [(width - EbookReader::Helpers::TextMetrics.visible_length(empty_text) + 10) / 2, 1].max,
                        empty_text)

          help_text = "#{COLOR_TEXT_DIM}Annotations you create while reading will appear here#{reset}"
          surface.write(bounds, mid + 2,
                        [(width - EbookReader::Helpers::TextMetrics.visible_length(help_text) + 10) / 2, 1].max,
                        help_text)
        end

        def render_annotations_list(surface, bounds, width, height, annotations, in_all)
          list_start_row = 4
          list_height = height - list_start_row - 2
          return if list_height <= 0

          start_index, visible_annotations = UI::ListHelpers.slice_visible(annotations, list_height, @selected)

          visible_annotations.each_with_index do |annotation, index|
            row = list_start_row + index
            abs_idx = start_index + index
            is_selected = (abs_idx == @selected)

            render_annotation_item(surface, bounds, row, width, annotation, is_selected,
                                   abs_idx, in_all)
          end
        end

        def render_annotation_item(surface, bounds, row, width, annotation, is_selected,
                                   absolute_index, in_all)
          # Extract annotation details
          text = (annotation[:text] || 'No text').to_s.tr("\n", ' ')
          note = (annotation[:note] || '').to_s.tr("\n", ' ')
          created = (annotation[:created_at] || '').to_s.split('T').first
          chapter = annotation[:chapter_index]

          # Column widths (match header)
          idx_w = 4
          ch_w = 6
          date_w = 10
          book_w = (in_all ? 12 : 0)
          avail = width - (idx_w + ch_w + date_w + book_w + 8)
          snippet_w = (avail * 0.6).to_i
          note_w = avail - snippet_w

          pointer = is_selected ? '▸' : ' '
          idx = pad_left((absolute_index + 1).to_s, idx_w)
          chv = chapter.nil? ? '-' : chapter.to_i
          ch_col = pad_right(chv.to_s, ch_w)
          snippet = pad_right(truncate_text(text, snippet_w), snippet_w)
          note_tr = pad_right(truncate_text(note, note_w), note_w)
          if in_all
            bp = annotation[:book_path]
            book = bp ? File.basename(bp) : ''
            book_col = pad_right(truncate_text(book, book_w), book_w)
            date_col = pad_right(truncate_text(created, date_w), date_w)
            line = [pointer, ' ', idx, '  ', ch_col, '  ', snippet, '  ', note_tr,
                    '  ', book_col, '  ', date_col].join
          else
            date_col = pad_right(truncate_text(created, date_w), date_w)
            line = [pointer, ' ', idx, '  ', ch_col, '  ', snippet, '  ', note_tr,
                    '  ', date_col].join
          end

          color = is_selected ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
          surface.write(bounds, row, 1, color + line + Terminal::ANSI::RESET)
        end

        # truncate_text provided by UI::TextUtils

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
