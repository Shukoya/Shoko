# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'time'

require_relative 'cache_paths'
require_relative 'atomic_file_writer'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # EpubCache manages reading and writing Marshal-based cache files that contain
    # the complete representation of an imported book plus any derived data
    # (pagination layouts, etc). Each EPUB is stored as a single file located at
    # `${XDG_CACHE_HOME:-~/.cache}/reader/<sha256>.cache`.
    class EpubCache
      CACHE_VERSION   = 2
      CACHE_EXTENSION = '.cache'

      CachePayload = Struct.new(
        :version,
        :source_sha256,
        :source_path,
        :source_mtime,
        :generated_at,
        :book,
        :layouts,
        keyword_init: true
      )

      BookData = Struct.new(
        :title,
        :language,
        :authors,
        :chapters,
        :toc_entries,
        :opf_path,
        :spine,
        :chapter_hrefs,
        :resources,
        :metadata,
        :container_path,
        :container_xml,
        keyword_init: true
      )

      CacheLoad = Struct.new(
        :payload,
        :cache_path,
        :source_path,
        :loaded_from_cache,
        keyword_init: true
      )

      class << self
        def cache_extension = CACHE_EXTENSION

        def cache_file?(path)
          File.file?(path) && File.extname(path).casecmp(CACHE_EXTENSION).zero?
        end

        def cache_path_for_sha(sha, cache_root: CachePaths.reader_root)
          File.join(cache_root, "#{sha}#{CACHE_EXTENSION}")
        end
      end

      attr_reader :cache_path, :source_path

      def initialize(path, cache_root: CachePaths.reader_root)
        @cache_root = cache_root
        @raw_path   = path
        @source_path = File.expand_path(path)
        @payload_cache = nil
        @payload_signature = nil
        @payload_signature = nil

        if self.class.cache_file?(@source_path)
          @cache_path = @source_path
          @source_type = :cache_file
          @source_sha = nil
        else
          raise EbookReader::FileNotFoundError, @source_path unless File.file?(@source_path)

          @source_type = :epub
          @source_sha = Digest::SHA256.file(@source_path).hexdigest
          @cache_path = self.class.cache_path_for_sha(@source_sha, cache_root: @cache_root)
        end
      end

      # Load the cache payload without applying source validation. Intended for
      # direct cache-file access (opening `.cache` files from the library).
      def read_cache(strict: false)
        payload = load_payload_from_disk
        return nil unless payload

        return payload if strict == false || payload_valid?(payload)

        invalidate!
        nil
      end

      # Load and validate the payload for the associated EPUB source. Returns nil
      # when the cache is missing, corrupt, or outdated.
      def load_for_source(strict: false)
        payload = load_payload_from_disk
        return nil unless payload
        return payload if payload_valid?(payload) && payload_matches_source?(payload, strict: strict)

        invalidate!
        nil
      end

      # Writes the provided book data to disk, producing a fresh payload.
      def write_book!(book_data)
        ensure_sha!
        payload = CachePayload.new(
          version: CACHE_VERSION,
          source_sha256: @source_sha,
          source_path: @source_path,
          source_mtime: safe_mtime(@source_path),
          generated_at: Time.now.utc,
          book: book_data,
          layouts: {}
        )
        write_payload(payload)
        payload
      rescue StandardError => e
        Logger.debug('EpubCache: failed to write cache', path: @cache_path, error: e.message)
        nil
      end

      # Returns a deep copy of the layout entry associated with the provided key,
      # or nil when not present/invalid.
      def load_layout(key)
        payload = load_payload_from_disk
        return nil unless payload

        layouts = payload.layouts || {}
        entry = layouts[key] || layouts[key.to_s] || layouts[key.to_sym]
        return nil unless entry

        deep_dup(entry)
      rescue StandardError
        nil
      end

      # Persistently mutates the layout map. The provided block receives the
      # mutable layout hash and is expected to set or delete entries as needed.
      def mutate_layouts!
        payload = load_payload_from_disk
        return false unless payload

        payload.layouts ||= {}
        yield(payload.layouts)
        write_payload(payload)
        true
      rescue StandardError => e
        Logger.debug('EpubCache: failed to update layouts', path: @cache_path, error: e.message)
        false
      end

      def invalidate!
        FileUtils.rm_f(@cache_path)
        @payload_cache = nil
        @payload_signature = nil
      rescue StandardError
        nil
      end

      def cache_file?
        @source_type == :cache_file
      end

      def sha256
        ensure_sha!
        @source_sha
      end

      private

      def ensure_sha!
        return if @source_sha

        @source_sha = Digest::SHA256.file(@source_path).hexdigest if @source_type == :epub
      end

      def load_payload_from_disk
        if @payload_cache && File.exist?(@cache_path)
          current_sig = file_signature(@cache_path)
          return @payload_cache if @payload_signature && current_sig && current_sig == @payload_signature
        end
        return nil unless File.exist?(@cache_path)

        raw = File.binread(@cache_path)
        obj = Marshal.load(raw)
        payload = coerce_payload(obj)
        return nil unless payload

        payload.layouts ||= {}
        @payload_cache = payload
        @payload_signature = file_signature(@cache_path)
        payload
      rescue StandardError => e
        Logger.debug('EpubCache: failed to load cache', path: @cache_path, error: e.message)
        invalidate!
        nil
      end

      def write_payload(payload)
        AtomicFileWriter.write_using(@cache_path, binary: true) do |io|
          io.write(Marshal.dump(payload))
        end
        @payload_cache = payload
        @payload_signature = file_signature(@cache_path)
      end

      def coerce_payload(obj)
        case obj
        when CachePayload
          obj
        when Hash
          book = obj[:book] || obj['book']
          unless book.is_a?(BookData)
            Logger.debug('EpubCache: invalid book payload type', type: book.class.name)
            return nil
          end

          CachePayload.new(
            version: obj[:version] || obj['version'],
            source_sha256: obj[:source_sha256] || obj['source_sha256'],
            source_path: obj[:source_path] || obj['source_path'],
            source_mtime: obj[:source_mtime] || obj['source_mtime'],
            generated_at: obj[:generated_at] || obj['generated_at'],
            book: book,
            layouts: obj[:layouts] || obj['layouts'] || {}
          )
        else
          Logger.debug('EpubCache: unexpected payload object', klass: obj.class.name)
          nil
        end
      end

      def payload_valid?(payload)
        payload.is_a?(CachePayload) &&
          payload.version.to_i == CACHE_VERSION &&
          payload.book.is_a?(BookData)
      end

      def payload_matches_source?(payload, strict:)
        return true if cache_file?

        ensure_sha!

        return false unless payload.source_sha256 == @source_sha

        source_mtime = safe_mtime(@source_path)
        payload_mtime = payload.source_mtime
        return true unless source_mtime && payload_mtime

        tolerance = strict ? 1e-3 : 1.0
        (source_mtime - payload_mtime).abs <= tolerance
      end

      def safe_mtime(path)
        File.mtime(path)&.utc
      rescue StandardError
        nil
      end

      def file_signature(path)
        return nil unless File.exist?(path)

        [safe_mtime(path)&.to_f, File.size?(path)]
      rescue StandardError
        nil
      end

      def deep_dup(obj)
        Marshal.load(Marshal.dump(obj))
      end
    end
  end
end
