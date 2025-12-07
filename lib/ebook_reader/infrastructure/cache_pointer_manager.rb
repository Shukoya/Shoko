# frozen_string_literal: true

require 'json'

require_relative 'atomic_file_writer'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Manages pointer files that reference serialized cache payloads on disk.
    class CachePointerManager
      POINTER_FORMAT  = 'reader-marshal-cache'
      POINTER_VERSION = 2
      POINTER_ENGINE  = 'marshal'
      POINTER_KEYS    = %w[format version sha256 source_path generated_at engine].freeze

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
          data['engine'].to_s == POINTER_ENGINE &&
          data['version'].to_i == POINTER_VERSION
      end
    end
  end
end
