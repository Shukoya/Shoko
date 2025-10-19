# frozen_string_literal: true

require_relative 'base_service'
require_relative '../../infrastructure/epub_cache'

module EbookReader
  module Domain
    module Services
      # Provides cache-related helpers so controllers can remain free of
      # infrastructure concerns.
      class CacheService < BaseService
        def initialize(dependencies)
          super
          @cache_factory = resolve_required(:epub_cache_factory)
          @cache_predicate = resolve_required(:epub_cache_predicate)
        end

        def cache_file?(path)
          @cache_predicate.call(path)
        end

        def valid_cache?(path)
          return false unless path && File.file?(path)
          return false unless cache_file?(path)

          cache = build_cache(path)
          !!cache&.read_cache(strict: true)
        rescue EbookReader::Error, StandardError
          false
        end

        def canonical_source_path(path)
          return path unless cache_file?(path)

          cache = build_cache(path)
          payload = cache&.read_cache(strict: false)
          source = payload&.source_path
          source && !source.empty? ? source : path
        rescue EbookReader::Error, StandardError
          path
        end

        def cache_for_document(document)
          path = cache_path_for_document(document)
          return nil unless path

          build_cache(path)
        rescue EbookReader::Error, StandardError
          nil
        end

        private

        def build_cache(path)
          @cache_factory.call(path)
        end

        def cache_path_for_document(document)
          return document.cache_path if document.respond_to?(:cache_path) && document.cache_path

          if document.respond_to?(:canonical_path) && document.canonical_path
            cache = @cache_factory.call(document.canonical_path)
            return cache.cache_path if cache && File.exist?(cache.cache_path)
          end

          nil
        rescue EbookReader::Error, StandardError
          nil
        end
      private

        def resolve_required(name)
          resolve(name)
        rescue StandardError => e
          raise ArgumentError, "Missing dependency #{name}: #{e.message}"
        end
      end
    end
  end
end
