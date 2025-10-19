# frozen_string_literal: true

require 'json'

require_relative 'atomic_file_writer'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Manages pointer files that reference entries in cache.sqlite3.
    class CachePointerManager
      POINTER_FORMAT  = 'reader-sqlite-cache'
      POINTER_VERSION = 1
      POINTER_KEYS    = %w[format version sha256 source_path generated_at].freeze

      def initialize(path)
        @path = path
      end

      attr_reader :path

      def read
        return nil unless File.exist?(path)

        content = File.read(path)
        return nil if content.nil? || content.empty?

        data = JSON.parse(content)
        return nil unless valid_pointer?(data)

        data
      rescue JSON::ParserError
        nil
      end

      def write(data)
        AtomicFileWriter.write_using(path) do |io|
          io.write(JSON.generate(data))
        end
      rescue StandardError => e
        Logger.debug('CachePointerManager: write failed', path:, error: e.message)
        false
      end

      private

      def valid_pointer?(data)
        POINTER_KEYS.all? { |key| data.key?(key) } &&
          data['format'] == POINTER_FORMAT &&
          data['version'].to_i == POINTER_VERSION
      end
    end
  end
end
