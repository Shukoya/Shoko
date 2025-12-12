# frozen_string_literal: true

require_relative '../errors'
require_relative 'epub_cache'
require_relative 'epub_importer'
require_relative 'logger'
require 'fileutils'

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
        cache = @cache_class.new(path, cache_root: @cache_root)
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
