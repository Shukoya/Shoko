# frozen_string_literal: true

require 'fileutils'
require 'json'

require_relative 'cache_paths'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Minimal marshal-backed cache store for EPUB payloads and layouts.
    # Avoids JSON and SQLite round-trips for hot paths.
    class MarshalCacheStore
      ENGINE = 'marshal'
      Payload = Struct.new(:metadata_row, :chapters, :resources, :layouts, keyword_init: true)
      MANIFEST_FILENAME = 'marshal_manifest.json'

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

        raw = File.binread(path)
        data = Marshal.load(raw)
        Payload.new(
          metadata_row: data[:metadata_row],
          chapters: data[:chapters] || [],
          resources: data[:resources] || [],
          layouts: load_layout_rows(sha)
        )
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: fetch failed', sha:, error: e.message)
        nil
      end

      def write_payload(sha:, source_path:, source_mtime:, generated_at:, serialized_book:, serialized_chapters:, serialized_resources:, serialized_layouts:)
        now = Time.now.utc.to_f
        metadata_row = stringify_keys(serialized_book)
        metadata_row['source_sha'] = sha
        metadata_row['source_path'] = source_path
        metadata_row['source_mtime'] = source_mtime&.to_f
        metadata_row['generated_at'] = generated_at&.to_f
        metadata_row['created_at'] = now
        metadata_row['updated_at'] = now
        metadata_row['engine'] = ENGINE
        payload = {
          metadata_row: metadata_row,
          chapters: serialized_chapters,
          resources: serialized_resources,
        }

        path = payload_path(sha)
        File.binwrite(path, Marshal.dump(payload))
        write_layouts(sha, serialized_layouts)
        update_manifest(metadata_row, serialized_resources)
        true
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: write failed', sha:, error: e.message)
        false
      end

      def load_layout(sha, key)
        file = layout_file(sha, key)
        return nil unless File.file?(file)

        Marshal.load(File.binread(file))
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: layout load failed', sha:, key:, error: e.message)
        nil
      end

      def fetch_layouts(sha)
        dir = layouts_dir(sha)
        return {} unless Dir.exist?(dir)

        layouts = {}
        Dir.children(dir).each do |entry|
          next unless entry.end_with?('.marshal')

          key = entry.sub(/\.marshal\z/, '')
          layouts[key] = Marshal.load(File.binread(File.join(dir, entry)))
        end
        layouts
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: layouts fetch failed', sha:, error: e.message)
        {}
      end

      def mutate_layouts(sha)
        layouts = fetch_layouts(sha)
        yield layouts
        write_layouts(sha, layouts)
        true
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: mutate layouts failed', sha:, error: e.message)
        false
      end

      def delete_payload(sha)
        FileUtils.rm_f(payload_path(sha))
        FileUtils.rm_rf(layouts_dir(sha))
        remove_from_manifest(sha)
        true
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: delete failed', sha:, error: e.message)
        false
      end

      def list_books
        manifest_rows(@cache_root)
      rescue StandardError
        []
      end

      def self.manifest_rows(cache_root)
        path = File.join(cache_root, MANIFEST_FILENAME)
        return [] unless File.file?(path)

        json = JSON.parse(File.read(path))
        json.is_a?(Array) ? json : []
      rescue StandardError
        []
      end

      private

      def payload_path(sha)
        File.join(@cache_root, "#{sha}.marshal")
      end

      def layouts_dir(sha)
        File.join(@cache_root, 'layouts', sha)
      end

      def layout_file(sha, key)
        File.join(layouts_dir(sha), "#{key}.marshal")
      end

      def write_layouts(sha, layouts_hash)
        dir = layouts_dir(sha)
        FileUtils.mkdir_p(dir)
        layouts_hash.each do |key, payload|
          File.binwrite(layout_file(sha, key), Marshal.dump(payload))
        end
      end

      def load_layout_rows(sha)
        layouts = fetch_layouts(sha)
        layouts.map do |key, payload|
          { 'key' => key, 'payload_json' => JSON.generate(payload) }
        end
      end

      def manifest_path
        File.join(@cache_root, MANIFEST_FILENAME)
      end

      def update_manifest(metadata_row, resources)
        size_bytes = Array(resources).sum { |res| res[:data].to_s.bytesize }
        row = metadata_row.merge('cache_size_bytes' => size_bytes)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == row['source_sha'] }
        manifest << row
        File.write(manifest_path, JSON.pretty_generate(manifest))
      rescue StandardError => e
        Logger.debug('MarshalCacheStore: manifest write failed', error: e.message)
      end

      def stringify_keys(hash)
        hash.transform_keys { |k| k.to_s }
      rescue StandardError
        hash || {}
      end

      def remove_from_manifest(sha)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == sha }
        File.write(manifest_path, JSON.pretty_generate(manifest))
      rescue StandardError
        nil
      end
    end
  end
end
