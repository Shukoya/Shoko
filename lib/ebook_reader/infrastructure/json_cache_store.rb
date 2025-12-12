# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

require_relative 'atomic_file_writer'
require_relative 'cache_paths'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # JSON-backed cache store for EPUB payloads + layouts.
    #
    # This store persists only primitive JSON data and keeps binary resources
    # as separate blobs on disk (referenced from the JSON payload).
    class JsonCacheStore
      ENGINE = 'json'
      FORMAT = 'reader-cache-payload'
      FORMAT_VERSION = 1

      Payload = Struct.new(:metadata_row, :chapters, :resources, :layouts, keyword_init: true)

      MANIFEST_FILENAME = 'cache_manifest.json'
      LEGACY_MANIFEST_FILENAME = 'marshal_manifest.json'

      SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

      MAX_LAYOUT_KEY_BYTES = 200
      LAYOUT_KEY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

      def initialize(cache_root: CachePaths.reader_root)
        @cache_root = cache_root
        FileUtils.mkdir_p(@cache_root)
      end

      def engine
        ENGINE
      end

      def fetch_payload(sha)
        path = payload_path(sha)
        return nil unless File.file?(path)

        json = File.read(path)
        data = JSON.parse(json)
        return nil unless valid_payload_file?(data)

        Payload.new(
          metadata_row: data.fetch('metadata_row', {}),
          chapters: data.fetch('chapters', []),
          resources: hydrate_resources(sha, data.fetch('resources', [])),
          layouts: fetch_layouts(sha)
        )
      rescue StandardError => e
        Logger.debug('JsonCacheStore: fetch failed', sha: sha.to_s, error: e.message)
        nil
      end

      def write_payload(sha:, source_path:, source_mtime:, generated_at:, serialized_book:, serialized_chapters:,
                        serialized_resources:, serialized_layouts:)
        now = Time.now.utc.to_f
        normalized_sha = normalize_sha!(sha)

        metadata_row = stringify_keys(serialized_book)
        metadata_row['source_sha'] = normalized_sha
        metadata_row['source_path'] = source_path
        metadata_row['source_mtime'] = source_mtime&.to_f
        metadata_row['generated_at'] = generated_at&.to_f
        metadata_row['created_at'] = now
        metadata_row['updated_at'] = now
        metadata_row['engine'] = ENGINE

        resources_index, size_bytes = persist_resources(normalized_sha, serialized_resources)

        payload = {
          'format' => FORMAT,
          'format_version' => FORMAT_VERSION,
          'engine' => ENGINE,
          'metadata_row' => metadata_row,
          'chapters' => serialized_chapters || [],
          'resources' => resources_index,
        }

        AtomicFileWriter.write(payload_path(normalized_sha), JSON.generate(payload))
        write_layouts(normalized_sha, serialized_layouts || {})
        update_manifest(metadata_row, cache_size_bytes: size_bytes)
        cleanup_legacy_marshal_files(normalized_sha)
        true
      rescue StandardError => e
        Logger.debug('JsonCacheStore: write failed', sha: sha.to_s, error: e.message)
        false
      end

      def load_layout(sha, key)
        file = layout_file(sha, key)
        return nil unless File.file?(file)

        JSON.parse(File.read(file))
      rescue StandardError => e
        Logger.debug('JsonCacheStore: layout load failed', sha: sha.to_s, key: key.to_s, error: e.message)
        nil
      end

      def fetch_layouts(sha)
        dir = layouts_dir(sha)
        return {} unless Dir.exist?(dir)

        layouts = {}
        Dir.children(dir).each do |entry|
          next unless entry.end_with?('.json')

          key = entry.sub(/\.json\z/, '')
          next unless layout_key_valid?(key)

          begin
            layouts[key] = JSON.parse(File.read(File.join(dir, entry)))
          rescue StandardError => e
            Logger.debug('JsonCacheStore: layout parse failed', sha: sha.to_s, key: key.to_s, error: e.message)
            next
          end
        end
        layouts
      rescue StandardError => e
        Logger.debug('JsonCacheStore: layouts fetch failed', sha: sha.to_s, error: e.message)
        {}
      end

      def mutate_layouts(sha)
        layouts = fetch_layouts(sha)
        yield layouts
        write_layouts(sha, layouts)
        true
      rescue StandardError => e
        Logger.debug('JsonCacheStore: mutate layouts failed', sha: sha.to_s, error: e.message)
        false
      end

      def delete_payload(sha)
        normalized_sha = normalize_sha!(sha)
        FileUtils.rm_f(payload_path(normalized_sha))
        FileUtils.rm_rf(layouts_dir(normalized_sha))
        FileUtils.rm_rf(resources_dir(normalized_sha))
        remove_from_manifest(normalized_sha)
        true
      rescue StandardError => e
        Logger.debug('JsonCacheStore: delete failed', sha: sha.to_s, error: e.message)
        false
      end

      def list_books
        self.class.manifest_rows(@cache_root)
      rescue StandardError
        []
      end

      def self.manifest_rows(cache_root)
        current = read_manifest_file(File.join(cache_root, MANIFEST_FILENAME))
        return current unless current.empty?

        read_manifest_file(File.join(cache_root, LEGACY_MANIFEST_FILENAME))
      rescue StandardError
        []
      end

      private

      def payload_path(sha)
        File.join(@cache_root, "#{normalize_sha!(sha)}.json")
      end

      def layouts_dir(sha)
        File.join(@cache_root, 'layouts', normalize_sha!(sha))
      end

      def layout_file(sha, key)
        File.join(layouts_dir(sha), "#{normalize_layout_key!(key)}.json")
      end

      def resources_dir(sha)
        File.join(@cache_root, 'resources', normalize_sha!(sha))
      end

      def resource_blob_path(sha, blob_key)
        File.join(resources_dir(sha), "#{blob_key}.bin")
      end

      def valid_payload_file?(data)
        return false unless data.is_a?(Hash)
        return false unless data['format'] == FORMAT
        return false unless data['format_version'].to_i == FORMAT_VERSION
        return false unless data['engine'].to_s == ENGINE
        return false unless data['metadata_row'].is_a?(Hash)
        return false unless data['chapters'].is_a?(Array)
        return false unless data['resources'].is_a?(Array)

        true
      rescue StandardError
        false
      end

      def hydrate_resources(sha, index_rows)
        Array(index_rows).map do |row|
          path = row.is_a?(Hash) ? (row['path'] || row[:path]) : nil
          blob = row.is_a?(Hash) ? (row['blob'] || row[:blob]) : nil
          next nil if path.to_s.empty? || blob.to_s.empty?

          data = File.binread(resource_blob_path(sha, blob.to_s))
          data.force_encoding(Encoding::BINARY)
          { path: path.to_s, data: data }
        rescue StandardError
          nil
        end.compact
      end

      def persist_resources(sha, resources_rows)
        dir = resources_dir(sha)
        FileUtils.mkdir_p(dir)

        rows = []
        total_bytes = 0
        Array(resources_rows).each do |row|
          path = row.is_a?(Hash) ? (row[:path] || row['path']) : nil
          data = row.is_a?(Hash) ? (row[:data] || row['data']) : nil
          next if path.to_s.empty?

          bytes = String(data).dup
          bytes.force_encoding(Encoding::BINARY)
          blob_key = Digest::SHA256.hexdigest(path.to_s)

          AtomicFileWriter.write(resource_blob_path(sha, blob_key), bytes, binary: true)

          total_bytes += bytes.bytesize
          rows << { 'path' => path.to_s, 'blob' => blob_key, 'bytesize' => bytes.bytesize }
        end

        [rows, total_bytes]
      end

      def write_layouts(sha, layouts_hash)
        dir = layouts_dir(sha)
        FileUtils.mkdir_p(dir)
        existing = Dir.exist?(dir) ? Dir.children(dir).select { |entry| entry.end_with?('.json') } : []

        written = []
        layouts_hash.each do |key, payload|
          normalized_key = normalize_layout_key!(key)
          file = File.join(dir, "#{normalized_key}.json")
          AtomicFileWriter.write(file, JSON.generate(payload))
          written << "#{normalized_key}.json"
        end

        stale = existing - written
        stale.each { |entry| FileUtils.rm_f(File.join(dir, entry)) }
      end

      def manifest_path
        File.join(@cache_root, MANIFEST_FILENAME)
      end

      def legacy_manifest_path
        File.join(@cache_root, LEGACY_MANIFEST_FILENAME)
      end

      def update_manifest(metadata_row, cache_size_bytes:)
        row = metadata_row.merge('cache_size_bytes' => cache_size_bytes.to_i)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == row['source_sha'] }
        manifest << row
        AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
        FileUtils.rm_f(legacy_manifest_path) if File.file?(legacy_manifest_path)
      rescue StandardError => e
        Logger.debug('JsonCacheStore: manifest write failed', error: e.message)
      end

      def remove_from_manifest(sha)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == sha }
        AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
        FileUtils.rm_f(legacy_manifest_path) if File.file?(legacy_manifest_path)
      rescue StandardError
        nil
      end

      def self.read_manifest_file(path)
        return [] unless File.file?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Array) ? data : []
      rescue StandardError
        []
      end
      private_class_method :read_manifest_file

      def stringify_keys(hash)
        (hash || {}).transform_keys(&:to_s)
      rescue StandardError
        hash || {}
      end

      def normalize_sha!(sha)
        value = sha.to_s.strip
        raise ArgumentError, 'sha is blank' if value.empty?
        raise ArgumentError, 'sha must be a 64-char hex digest' unless SHA256_HEX_PATTERN.match?(value)

        value.downcase
      end

      def layout_key_valid?(key)
        normalize_layout_key!(key)
        true
      rescue ArgumentError
        false
      end

      def normalize_layout_key!(key)
        value = key.to_s
        raise ArgumentError, 'layout key is blank' if value.empty?
        raise ArgumentError, 'layout key too long' if value.bytesize > MAX_LAYOUT_KEY_BYTES
        raise ArgumentError, 'layout key contains null byte' if value.include?("\0")
        raise ArgumentError, 'layout key contains path separator' if value.include?('/') || value.include?('\\')
        raise ArgumentError, 'layout key has invalid characters' unless LAYOUT_KEY_PATTERN.match?(value)

        value
      end

      def cleanup_legacy_marshal_files(sha)
        FileUtils.rm_f(File.join(@cache_root, "#{sha}.marshal"))

        legacy_layouts = File.join(@cache_root, 'layouts', sha)
        if Dir.exist?(legacy_layouts)
          Dir.children(legacy_layouts).each do |entry|
            next unless entry.end_with?('.marshal')

            FileUtils.rm_f(File.join(legacy_layouts, entry))
          end
        end

      rescue StandardError
        nil
      end
    end
  end
end
