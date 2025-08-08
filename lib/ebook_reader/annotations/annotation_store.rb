# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module EbookReader
  module Annotations
    # Manages persistence of annotations
    class AnnotationStore
      CONFIG_DIR = File.expand_path('~/.config/reader')
      ANNOTATIONS_FILE = File.join(CONFIG_DIR, 'annotations.json')

      class << self
        def add(epub_path, text, note, range, chapter_index)
          annotations = load_all
          book_annotations = annotations[epub_path] || []

          new_annotation = {
            'id' => Time.now.to_f,
            'text' => text,
            'note' => note,
            'range' => range,
            'chapter_index' => chapter_index,
            'created_at' => Time.now.iso8601,
          }

          book_annotations << new_annotation
          annotations[epub_path] = book_annotations
          save_all(annotations)
        end

        def get(epub_path)
          load_all[epub_path] || []
        end

        def update(epub_path, id, note)
          annotations = load_all
          book_annotations = annotations[epub_path] || []

          annotation = book_annotations.find { |a| a['id'] == id }
          return unless annotation

          annotation['note'] = note
          annotation['updated_at'] = Time.now.iso8601
          save_all(annotations)
        end

        def delete(epub_path, id)
          annotations = load_all
          book_annotations = annotations[epub_path] || []
          book_annotations.reject! { |a| a['id'] == id }

          if book_annotations.empty?
            annotations.delete(epub_path)
          else
            annotations[epub_path] = book_annotations
          end

          save_all(annotations)
        end

        private

        def load_all
          return {} unless File.exist?(ANNOTATIONS_FILE)

          JSON.parse(File.read(ANNOTATIONS_FILE))
        rescue StandardError
          {}
        end

        def save_all(annotations)
          FileUtils.mkdir_p(CONFIG_DIR)
          File.write(ANNOTATIONS_FILE, JSON.pretty_generate(annotations))
        rescue StandardError
          nil
        end
      end
    end
  end
end
