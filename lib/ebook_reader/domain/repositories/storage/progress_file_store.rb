# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative '../../../constants'
require_relative 'file_store_utils'

module EbookReader
  module Domain
    module Repositories
      module Storage
        # File-backed progress storage under Domain.
        # Persists progress to ~/.config/reader/progress.json
        class ProgressFileStore
          def save(path, chapter_index, line_offset)
            all = load_all
            all[path.to_s] = {
              'chapter' => chapter_index,
              'line_offset' => line_offset,
              'timestamp' => Time.now.iso8601,
            }
            save_all(all)
            true
          rescue StandardError
            false
          end

          def load(path)
            all = load_all
            all[path.to_s]
          rescue StandardError
            nil
          end

          def load_all
            FileStoreUtils.load_json_or_empty(file_path)
          end

          private

          def save_all(data)
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, JSON.pretty_generate(data))
          end

          def file_path
            File.join(File.expand_path('~/.config/reader'), EbookReader::Constants::PROGRESS_FILE)
          end
        end
      end
    end
  end
end
