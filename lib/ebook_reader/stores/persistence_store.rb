# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative '../constants'

module EbookReader
  module Stores
    # Unified persistence for reading progress and bookmarks
    class PersistenceStore
      STATE_FILE = File.join(Constants::CONFIG_DIR, 'reading_state.yml')

      def initialize
        FileUtils.mkdir_p(Constants::CONFIG_DIR)
      rescue StandardError
        nil
      end

      def load_reading_state(book_id)
        data = load_all
        (data[book_id] || {}).transform_keys(&:to_sym)
      end

      def save_reading_state(book_id, chapter:, offset:, bookmarks: [])
        data = load_all
        data[book_id] = {
          'chapter' => chapter,
          'offset' => offset,
          'bookmarks' => Array(bookmarks).map { |bm| bookmark_hash(bm) },
          'timestamp' => Time.now.to_s,
        }
        File.write(STATE_FILE, data.to_yaml)
      rescue StandardError
        nil
      end

      private

      def load_all
        return {} unless File.exist?(STATE_FILE)

        YAML.load_file(STATE_FILE) || {}
      rescue StandardError
        {}
      end

      def bookmark_hash(bm)
        if bm.respond_to?(:to_h)
          bm.to_h
        else
          bm
        end
      end
    end
  end
end
