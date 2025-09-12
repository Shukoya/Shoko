# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require_relative 'cache_paths'
require_relative '../serializers'

module EbookReader
  module Infrastructure
    # EpubCache handles hashing, cache directory management, file copying, and
    # manifest read/write for EPUB caching.
    class EpubCache
      MANIFEST_VERSION = 1
      Manifest = Struct.new(:title, :author_str, :authors, :opf_path, :spine, :epub_path,
                            keyword_init: true)

      def initialize(epub_path)
        @epub_path = epub_path
        @sha = Digest::SHA256.file(epub_path).hexdigest
        @cache_dir = File.join(CachePaths.reader_root, @sha)
      end

      attr_reader :cache_dir, :sha

      # Load manifest if present (msgpack preferred if available)
      # Returns Manifest or nil.
      def load_manifest
        path, serializer = locate_manifest
        return nil unless path

        data = serializer.load_file(path)
        return nil unless valid_manifest_data?(data)
        return nil unless validate_files_present(data)

        to_manifest(data)
      rescue StandardError => e
        EbookReader::Infrastructure::Logger.debug('EpubCache: failed to load manifest',
                                                  error: e.message)
        nil
      end

      # Write manifest atomically (msgpack preferred when available)
      def write_manifest!(meta)
        FileUtils.mkdir_p(@cache_dir)
        serializer = select_serializer
        final = File.join(@cache_dir, serializer.manifest_filename)
        tmp = "#{final}.tmp"
        serializer.dump_file(tmp, manifest_to_h(meta))
        File.rename(tmp, final)
      rescue StandardError => e
        EbookReader::Infrastructure::Logger.debug('EpubCache: failed to write manifest',
                                                  error: e.message)
      ensure
        begin
          FileUtils.rm_f(tmp) if defined?(tmp) && File.exist?(tmp)
        rescue StandardError
          # ignore
        end
      end

      # Populate cache from the original EPUB using a provided Zip::File instance
      # for performance. Copies container.xml, OPF, and spine XHTML files.
      def populate!(zip, opf_path, spine_paths)
        FileUtils.mkdir_p(@cache_dir)
        copy_zip_entry(zip, 'META-INF/container.xml')
        copy_zip_entry(zip, opf_path)
        spine_paths.each { |p| copy_zip_entry(zip, p) }
      end

      # Convert relative path within the EPUB to the cache absolute path
      def cache_abs_path(rel)
        File.join(@cache_dir, rel)
      end

      private

      def valid_manifest_data?(h)
        return false unless h.is_a?(Hash)

        # Accept both versioned and legacy manifests; prefer versioned
        ver = h['version']
        ver.nil? || ver.to_i <= MANIFEST_VERSION
      end

      def validate_files_present(h)
        # Basic validation: ensure container.xml, OPF and spine files exist
        opf = h['opf_path'].to_s
        spine = Array(h['spine']).map(&:to_s)
        return false if opf.empty? || spine.empty?
        return false unless File.exist?(cache_abs_path('META-INF/container.xml'))
        return false unless File.exist?(cache_abs_path(opf))

        spine.all? { |rel| File.exist?(cache_abs_path(rel)) }
      rescue StandardError
        false
      end

      def copy_zip_entry(zip, rel_path)
        dest = cache_abs_path(rel_path)
        FileUtils.mkdir_p(File.dirname(dest))
        File.binwrite(dest, zip.read(rel_path))
      rescue StandardError => e
        EbookReader::Infrastructure::Logger.debug('EpubCache: copy failed', entry: rel_path,
                                                                            error: e.message)
      end

      def locate_manifest
        mp = File.join(@cache_dir, 'manifest.msgpack')
        js = File.join(@cache_dir, 'manifest.json')
        if File.exist?(mp) && EbookReader::Infrastructure::SerializerSupport.msgpack_available?
          [mp, EbookReader::Infrastructure::MessagePackSerializer.new]
        elsif File.exist?(js)
          [js, EbookReader::Infrastructure::JSONSerializer.new]
        else
          [nil, nil]
        end
      end

      def select_serializer
        EbookReader::Infrastructure::SerializerSupport.msgpack_available? ? EbookReader::Infrastructure::MessagePackSerializer.new : EbookReader::Infrastructure::JSONSerializer.new
      end

      def to_manifest(h)
        return nil unless h.is_a?(Hash)

        Manifest.new(
          title: h['title'].to_s,
          author_str: h['author'].to_s,
          authors: Array(h['authors']).map(&:to_s),
          opf_path: h['opf_path'].to_s,
          spine: Array(h['spine']).map(&:to_s),
          epub_path: h['epub_path'].to_s
        )
      end

      def manifest_to_h(m)
        {
          'version' => MANIFEST_VERSION,
          'title' => m.title.to_s,
          'author' => m.author_str.to_s,
          'authors' => Array(m.authors).map(&:to_s),
          'opf_path' => m.opf_path.to_s,
          'spine' => Array(m.spine).map(&:to_s),
          'epub_path' => m.epub_path.to_s,
        }
      end
    end

    # Serializers moved to lib/ebook_reader/serializers.rb (outside infra path)
  end
end
