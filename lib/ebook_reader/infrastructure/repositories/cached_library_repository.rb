# frozen_string_literal: true

require_relative '../cache_paths'
require_relative '../epub_cache'

module EbookReader
  module Infrastructure
    module Repositories
      # Provides read-only access to cached library metadata on disk.
      class CachedLibraryRepository
        def initialize(cache_root: Infrastructure::CachePaths.reader_root)
          @cache_root = cache_root
        end

        def list_entries
          return [] unless File.directory?(@cache_root)

          Dir.children(@cache_root).sort.each_with_object([]) do |entry, acc|
            next unless entry.end_with?(Infrastructure::EpubCache.cache_extension)

            cache_path = File.join(@cache_root, entry)
            payload = load_payload(cache_path)
            next unless payload

            acc << build_entry(cache_path, payload)
          end
        end

        private

        def load_payload(path)
          cache = Infrastructure::EpubCache.new(path)
          cache.read_cache(strict: true)
        rescue EbookReader::Error, StandardError
          nil
        end

        def build_entry(cache_path, payload)
          book = payload.book
          metadata = book.metadata || {}
          authors = Array(book.authors).join(', ')

          {
            title: present_or_default(book.title, 'Unknown'),
            authors: authors,
            year: metadata[:year].to_s,
            size_bytes: safe_file_size(cache_path),
            open_path: cache_path,
            epub_path: payload.source_path.to_s,
          }
        end

        def present_or_default(value, fallback)
          str = value.to_s.strip
          str.empty? ? fallback : value
        end

        def safe_file_size(path)
          File.size(path)
        rescue StandardError
          0
        end
      end
    end
  end
end
