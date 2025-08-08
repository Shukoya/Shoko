# frozen_string_literal: true

require_relative '../../annotations/annotation_store'

module EbookReader
  module UI
    module Screens
      # Displays all annotations, grouped by book
      class AnnotationsScreen
        attr_accessor :selected_book_index, :selected_annotation_index

        def initialize
          @annotations_by_book = Annotations::AnnotationStore.send(:load_all)
          @books = @annotations_by_book.keys
          @selected_book_index = 0
          @selected_annotation_index = 0
          @scroll_offset = 0
          @popup = nil
          @renderer = UI::MainMenuRenderer.new(EbookReader::Config.new)
        end

        def draw(height, width)
          @renderer.render_annotations_screen(
            UI::MainMenuRenderer::AnnotationsContext.new(
              height: height,
              width: width,
              books: @books,
              annotations_by_book: @annotations_by_book,
              selected_book_index: @selected_book_index,
              selected_annotation_index: @selected_annotation_index,
              popup: @popup && UI::MainMenuRenderer::PopupContext.new(
                title: @popup[:title], text: @popup[:text], visible: true
              )
            )
          )
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
      end
    end
  end
end
