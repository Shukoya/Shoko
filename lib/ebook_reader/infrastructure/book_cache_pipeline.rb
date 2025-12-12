# frozen_string_literal: true

require_relative '../errors'
require_relative 'epub_cache'
require_relative 'epub_importer'
require_relative 'json_cache_store'
require_relative 'cache_pointer_manager'
require_relative 'logger'
require_relative 'source_fingerprint'
require 'fileutils'
require 'time'

module EbookReader
  module Infrastructure
    # Coordinates importing EPUB files and storing/loading JSON-backed caches.
    # Provides a single entry point that ensures cache integrity, re-importing
    # whenever a cache is missing, corrupted, or outdated.
    class BookCachePipeline
      Result = Struct.new(
        :book,
        :cache_path,
        :source_path,
        :loaded_from_cache,
        :payload,
        keyword_init: true
      )

      def initialize(cache_class: EpubCache, cache_root: CachePaths.reader_root)
        @cache_class = cache_class
        @cache_root = cache_root
      end

      def load(path, formatting_service: nil)
        expanded = File.expand_path(path)

        if fast_source_path?(expanded)
          fast = fast_load_for_source(expanded, formatting_service)
          return fast if fast
        end

        cache = @cache_class.new(expanded, cache_root: @cache_root)
        payload = cache.cache_file? ? cache.read_cache(strict: true) : cache.load_for_source(strict: true)
        payload ||= cache.load_for_source(strict: false)

        if payload
          rebuilt = cache_incomplete?(payload.book)
          payload = rebuild_cache(cache, formatting_service) if rebuilt
          return Result.new(
            book: payload.book,
            cache_path: cache.cache_path,
            source_path: payload.source_path || cache.source_path,
            loaded_from_cache: !rebuilt,
            payload: payload
          )
        end

        if cache.cache_file?
          rebuilt = rebuild_from_pointer(cache, formatting_service)
          return rebuilt if rebuilt

          raise EbookReader::CacheLoadError, cache.cache_path
        end

        importer = EpubImporter.new(formatting_service:)
        book_data = importer.import(cache.source_path)
        cache.write_book!(book_data)
        payload = cache.load_for_source(strict: true) || cache.load_for_source(strict: false)
        raise EbookReader::CacheLoadError.new(cache.cache_path, 'cache write failed') unless payload

        Result.new(
          book: payload.book,
          cache_path: cache.cache_path,
          source_path: payload.source_path || cache.source_path,
          loaded_from_cache: false,
          payload: payload
        )
      rescue EbookReader::Error
        raise
      rescue StandardError => e
        Logger.error('Book cache pipeline failed', path: path, error: e.message)
        raise EbookReader::EPUBParseError.new(e.message, path)
      end

      private

      def cache_incomplete?(book)
        chapters = Array(book&.chapters)
        return true if chapters.empty?

        chapters.any? { |ch| ch.nil? || ch.raw_content.nil? || ch.raw_content.to_s.empty? }
      rescue StandardError
        true
      end

      def rebuild_cache(cache, formatting_service)
        importer = EpubImporter.new(formatting_service:)
        book_data = importer.import(cache.source_path)
        cache.write_book!(book_data)
        cache.load_for_source(strict: true) || cache.load_for_source(strict: false)
      end

      def fast_source_path?(expanded)
        return false if @cache_class.cache_file?(expanded)

        File.file?(expanded)
      rescue StandardError
        false
      end

      def fast_load_for_source(source_path, formatting_service)
        stat = File.stat(source_path)
        source_mtime = stat.mtime.utc
        source_size_bytes = stat.size

        sha = sha_from_manifest(source_path, source_mtime, source_size_bytes)
        return nil unless sha

        pointer_path = @cache_class.cache_path_for_sha(sha, cache_root: @cache_root)
        return nil unless pointer_path

        ensure_pointer_file(pointer_path, sha, source_path)

        cache = @cache_class.new(pointer_path, cache_root: @cache_root)

        loaded_from_cache = true
        payload = cache.read_cache(strict: true)
        unless payload
          loaded_from_cache = false
          payload = rebuild_cache(cache, formatting_service)
        end
        return nil unless payload

        rebuilt = cache_incomplete?(payload.book)
        if rebuilt
          loaded_from_cache = false
          payload = rebuild_cache(cache, formatting_service)
          return nil unless payload
        end

        Result.new(
          book: payload.book,
          cache_path: cache.cache_path,
          source_path: payload.source_path || cache.source_path,
          loaded_from_cache: loaded_from_cache,
          payload: payload
        )
      rescue StandardError => e
        Logger.debug('Fast cache load failed', path: source_path, error: e.message)
        nil
      end

      def sha_from_manifest(source_path, source_mtime, source_size_bytes)
        rows = JsonCacheStore.manifest_rows(@cache_root)
        return nil if rows.empty?

        path_matches = rows.select { |row| row.is_a?(Hash) && row['source_path'].to_s == source_path }
        return nil if path_matches.empty?

        mtime_matches = path_matches.select do |row|
          raw_mtime = row['source_mtime']
          next false if raw_mtime.nil?

          (raw_mtime.to_f - source_mtime.to_f).abs <= 1.0
        end
        return nil if mtime_matches.empty?

        size_matches = mtime_matches.select do |row|
          raw_size = row['source_size_bytes']
          raw_size.nil? || raw_size.to_i == source_size_bytes.to_i
        end
        return nil if size_matches.empty?

        fingerprint_matches = size_matches
        if size_matches.any? { |row| row['source_fingerprint'].to_s.strip != '' }
          fingerprint = SourceFingerprint.compute(source_path)
          return nil unless fingerprint

          fingerprint_matches = size_matches.select do |row|
            raw_fp = row['source_fingerprint'].to_s.strip
            raw_fp.empty? || raw_fp == fingerprint
          end
          return nil if fingerprint_matches.empty?
        end

        best = fingerprint_matches.max_by { |row| row['updated_at'].to_f }
        return nil unless best

        sha = best['source_sha'].to_s.strip
        sha.empty? ? nil : sha
      rescue StandardError
        nil
      end

      def ensure_pointer_file(pointer_path, sha, source_path)
        manager = CachePointerManager.new(pointer_path)
        existing = manager.read
        return if existing && existing['sha256'] == sha && existing['source_path'].to_s == source_path

        metadata = {
          'format' => CachePointerManager::POINTER_FORMAT,
          'version' => CachePointerManager::POINTER_VERSION,
          'sha256' => sha,
          'source_path' => source_path,
          'generated_at' => Time.now.utc.iso8601,
          'engine' => JsonCacheStore::ENGINE
        }

        manager.write(metadata)
      rescue StandardError
        nil
      end

      def rebuild_from_pointer(cache, formatting_service)
        source = cache.source_path
        return nil if source.nil? || source.to_s.empty?
        return nil if @cache_class.cache_file?(source)
        return nil unless File.file?(source)

        rebuilt = load(source, formatting_service: formatting_service)
        begin
          if rebuilt && rebuilt.cache_path && File.expand_path(rebuilt.cache_path) != File.expand_path(cache.cache_path)
            FileUtils.rm_f(cache.cache_path)
          end
        rescue StandardError
          nil
        end
        rebuilt
      rescue StandardError => e
        Logger.error('Pointer cache rebuild failed', cache: cache.cache_path, source: source, error: e.message)
        nil
      end
    end
  end
end
