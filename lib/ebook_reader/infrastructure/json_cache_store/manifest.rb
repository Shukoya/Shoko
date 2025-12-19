# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Manifest helpers for `JsonCacheStore` (cache listing + legacy migration).
    class JsonCacheStore
      private

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
    end
  end
end
