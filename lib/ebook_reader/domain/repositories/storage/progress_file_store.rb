# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative '../../../constants'
require_relative 'file_store_utils'
# Domain storage helpers should operate via injected services to avoid reaching into infrastructure.

module EbookReader
  module Domain
    module Repositories
      module Storage
        # File-backed progress storage under Domain.
        # Persists progress to ~/.config/reader/progress.json
        class ProgressFileStore
          def initialize(file_writer:, path_service:)
            @file_writer = file_writer
            @path_service = path_service
          end

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

          attr_reader :file_writer, :path_service

          def save_all(data)
            payload = JSON.pretty_generate(data)
            file_writer.write(file_path, payload)
          end

          def file_path
            path_service.reader_config_path(EbookReader::Constants::PROGRESS_FILE)
          end
        end
      end
    end
  end
end
