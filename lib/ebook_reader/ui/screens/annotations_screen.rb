# frozen_string_literal: true

require_relative '../../annotations/annotation_store'
require_relative '../../constants/ui_constants'
require_relative '../../components/surface'
require_relative '../../components/rect'

module EbookReader
  module UI
    module Screens
      # Displays all annotations, grouped by book
      class AnnotationsScreen
        include EbookReader::Constants

        attr_accessor :selected_book_index, :selected_annotation_index

        def initialize
          @annotations_by_book = Annotations::AnnotationStore.send(:load_all)
          @books = @annotations_by_book.keys
          @selected_book_index = 0
          @selected_annotation_index = 0
          @scroll_offset = 0
          @popup = nil
          @renderer = nil
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)

          if @popup
            render_popup(surface, bounds, height, width)
            return
          end

          surface.write(bounds, 1, 2, "#{UIConstants::COLOR_TEXT_ACCENT}All Annotations#{Terminal::ANSI::RESET}")
          surface.write(bounds, 2, 1, UIConstants::BORDER_PRIMARY + ('─' * width) + Terminal::ANSI::RESET)

          row = 4
          @books.each_with_index do |book_path, i|
            break if row > height - 3

            book_title = File.basename(book_path.to_s, '.epub')
            if i == @selected_book_index
              surface.write(bounds, row, 2,
                            UIConstants::SELECTION_POINTER_COLOR + UIConstants::SELECTION_POINTER + UIConstants::SELECTION_HIGHLIGHT + book_title + Terminal::ANSI::RESET)
              row += 1
              (@annotations_by_book[book_path] || []).each_with_index do |annotation, j|
                break if row > height - 3

                render_annotation_item(surface, bounds, annotation, j, row, width,
                                       j == @selected_annotation_index)
                row += 2
              end
            else
              surface.write(bounds, row, 2, "  #{book_title}")
              row += 1
            end

            row += 1
          end

          footer_text = '↑↓/jk: Navigate | Enter: Edit | d: Delete | q: Back'
          surface.write(bounds, height - 1, 2, UIConstants::COLOR_TEXT_DIM + footer_text + Terminal::ANSI::RESET)
          surface.write(bounds, height - 2, 1, UIConstants::BORDER_PRIMARY + ('─' * width) + Terminal::ANSI::RESET)
        end

        def show_annotation_popup
          annotation = current_annotation
          return unless annotation

          title = "Annotation from #{File.basename(current_book_path, '.epub')}"
          text = "Text: #{annotation['text']}\n\nNote: #{annotation['note']}"
          @popup = { title: title, text: text }
        end

        def handle_popup_input(key)
          return unless popup_visible?

          @popup = nil if ["\e", "\r"].include?(key)
        end

        def popup_visible?
          !@popup.nil?
        end

        def book_count
          @books.length
        end

        def current_book_path
          @books[@selected_book_index]
        end

        def current_annotation
          return nil if @books.empty? || !@annotations_by_book[current_book_path]

          @annotations_by_book[current_book_path][@selected_annotation_index]
        end

        def book_count
          @books.length
        end

        def annotation_count_for_selected_book
          return 0 if @books.empty? || !@annotations_by_book[@books[@selected_book_index]]

          @annotations_by_book[@books[@selected_book_index]].length
        end

        private

        def render_annotation_item(surface, bounds, annotation, _index, row, width, selected)
          text = annotation['text'].to_s.tr("\n", ' ').strip
          note = annotation['note'].to_s.tr("\n", ' ').strip
          color = selected ? UIConstants::SELECTION_HIGHLIGHT : UIConstants::COLOR_TEXT_PRIMARY
          surface.write(bounds, row, 4, color + "• #{text[0, width - 6]}" + Terminal::ANSI::RESET)
          surface.write(bounds, row + 1, 6, UIConstants::COLOR_TEXT_DIM + note[0, width - 8] + Terminal::ANSI::RESET)
        end

        def render_popup(surface, bounds, height, width)
          title = @popup[:title]
          text = @popup[:text]
          lines = text.to_s.split("\n")

          box_width = [lines.map(&:length).max.to_i + 4, title.length + 4, 20].max.clamp(20,
                                                                                         width - 4)
          box_height = [lines.length + 4, 5].max.clamp(5, height - 4)
          start_row = [(height - box_height) / 2, 2].max
          start_col = [(width - box_width) / 2, 2].max

          # Box border
          surface.write(bounds, start_row, start_col, "╭#{'─' * (box_width - 2)}╮")
          surface.write(bounds, start_row, start_col + 2, '[ Annotation ]')
          (1...(box_height - 1)).each do |i|
            surface.write(bounds, start_row + i, start_col, '│')
            surface.write(bounds, start_row + i, start_col + box_width - 1, '│')
          end
          surface.write(bounds, start_row + box_height - 1, start_col,
                        "╰#{'─' * (box_width - 2)}╯")

          # Title and content
          surface.write(bounds, start_row + 1, start_col + 2,
                        UIConstants::SELECTION_HIGHLIGHT + title + Terminal::ANSI::RESET)
          lines.each_with_index do |line, i|
            break if i >= box_height - 4

            surface.write(bounds, start_row + 2 + i, start_col + 2,
                          UIConstants::COLOR_TEXT_PRIMARY + line[0, box_width - 4] + Terminal::ANSI::RESET)
          end
        end
      end
    end
  end
end
