# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative 'file_store_utils'
require_relative '../../config_paths'
# Domain storage helpers should operate via injected services to avoid reaching into infrastructure.

module Shoko
  module Adapters::Storage::Repositories::Storage
    # File-backed progress storage under Domain.
    # Persists progress to ${XDG_CONFIG_HOME:-~/.config}/shoko/progress.json
    class ProgressFileStore
      FILE_NAME = 'progress.json'

      def initialize(file_writer:)
        @file_writer = file_writer
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

      attr_reader :file_writer

      def save_all(data)
        payload = JSON.pretty_generate(data)
        file_writer.write(file_path, payload)
      end

      def file_path
        Adapters::Storage::ConfigPaths.config_path(FILE_NAME)
      end
    end
  end
end
