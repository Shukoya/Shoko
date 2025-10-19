# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../atomic_file_writer'
require_relative '../cache_paths'
require_relative '../cache_store'
require_relative '../cache_pointer_manager'
require_relative '../epub_cache'

module EbookReader
  module Infrastructure
    module Repositories
      # Provides read-only access to cached library metadata on disk.
      class CachedLibraryRepository
        def initialize(cache_root: Infrastructure::CachePaths.reader_root, store: nil)
          @cache_root = cache_root
          @cache_store = store || Infrastructure::CacheStore.new(cache_root:)
        end

        def list_entries
          rows = fetch_rows
          return [] if rows.empty?

          rows.map { |row| build_entry_from_row(row) }
        end

        private

        def fetch_rows
          @cache_store.list_books
        end

        def build_entry_from_row(row)
          pointer_path = Infrastructure::EpubCache.cache_path_for_sha(row['source_sha'], cache_root: @cache_root)
          ensure_pointer_file(row, pointer_path)

          metadata = parse_json_object(row['metadata_json'])
          authors = parse_json_array(row['authors_json']).map(&:to_s)

          {
            title: present_or_default(row['title'], 'Unknown'),
            authors: authors.join(', '),
            year: extract_year(metadata),
            size_bytes: (row['cache_size_bytes'] || safe_file_size(pointer_path)).to_i,
            open_path: pointer_path,
            epub_path: row['source_path'].to_s,
          }
        end

        def ensure_pointer_file(row, path)
          return path if File.exist?(path) || row['source_sha'].to_s.empty?

          generated_at = begin
            raw = row['generated_at']
            raw ? Time.at(raw.to_f).utc.iso8601 : Time.now.utc.iso8601
          rescue StandardError
            Time.now.utc.iso8601
          end

          metadata = {
            'format' => Infrastructure::CachePointerManager::POINTER_FORMAT,
            'version' => Infrastructure::CachePointerManager::POINTER_VERSION,
            'sha256' => row['source_sha'],
            'source_path' => row['source_path'],
            'generated_at' => generated_at
          }

          Infrastructure::CachePointerManager.new(path).write(metadata)
          path
        rescue StandardError
          path
        end

        def parse_json_object(value)
          return {} unless value

          parsed = JSON.parse(value)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def parse_json_array(value)
          return [] unless value

          parsed = JSON.parse(value)
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError
          []
        end

        def extract_year(metadata)
          return '' unless metadata.respond_to?(:[])

          year = metadata['year'] || metadata[:year]
          year ? year.to_s : ''
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
