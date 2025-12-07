# frozen_string_literal: true

require_relative '../errors'
require_relative 'epub_cache'
require_relative 'epub_importer'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Coordinates importing EPUB files and storing/loading Marshal-backed caches.
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
          return Result.new(
            book: payload.book,
            cache_path: cache.cache_path,
            source_path: payload.source_path || cache.source_path,
            loaded_from_cache: true,
            payload: payload
          )
        end

        raise EbookReader::CacheLoadError, cache.cache_path if cache.cache_file?

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
    end
  end
end
