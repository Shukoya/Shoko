# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative '../../../constants'
require_relative '../../../infrastructure/atomic_file_writer'

module EbookReader
  module Domain
    module Repositories
      module Storage
        # File-backed annotation storage under Domain.
        # Persists annotations to ~/.config/reader/annotations.json
        class AnnotationFileStore
          def all
            load_all
          rescue StandardError
            {}
          end

          def get(path)
            (load_all[path.to_s] || []).dup
          rescue StandardError
            []
          end

          def add(path, text, note, range, chapter_index, page_meta = nil)
            data = load_all
            key = path.to_s
            list = data[key] || []
            now = Time.now
            ann = {
              'id' => now.to_f.to_s,
              'text' => text.to_s,
              'note' => note.to_s,
              'range' => range,
              'chapter_index' => chapter_index,
              'created_at' => now.iso8601,
            }
            if page_meta.is_a?(Hash)
              ann['page_current'] = page_meta[:current] || page_meta['current']
              ann['page_total'] = page_meta[:total] || page_meta['total']
              ann['page_mode'] = page_meta[:type] || page_meta['type']
            end
            list << ann
            data[key] = list
            save_all(data)
            true
          rescue StandardError
            false
          end

          def update(path, id, note)
            data = load_all
            key = path.to_s
            list = data[key] || []
            ann = list.find { |a| a['id'] == id }
            return false unless ann

            ann['note'] = note
            ann['updated_at'] = Time.now.iso8601
            data[key] = list
            save_all(data)
            true
          rescue StandardError
            false
          end

          def delete(path, id)
            data = load_all
            key = path.to_s
            list = data[key] || []
            list.reject! { |a| a['id'] == id }
            list.empty? ? data.delete(key) : data[key] = list
            save_all(data)
            true
          rescue StandardError
            false
          end

          private

          def load_all
            return {} unless File.exist?(file_path)

            JSON.parse(File.read(file_path))
          end

          def save_all(data)
            payload = JSON.pretty_generate(data)
            EbookReader::Infrastructure::AtomicFileWriter.write(file_path, payload)
          end

          def file_path
            File.join(File.expand_path('~/.config/reader'), 'annotations.json')
          end
        end
      end
    end
  end
end
