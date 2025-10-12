# frozen_string_literal: true

require_relative 'epub_cache'
require_relative 'perf_tracer'

module EbookReader
  module Infrastructure
    # Persists dynamic pagination layouts inside the Marshal cache file for a book.
    module PaginationCache
      module_function

      SCHEMA_VERSION = 1

      def layout_key(width, height, view_mode, line_spacing)
        "#{width}x#{height}_#{view_mode}_#{line_spacing}"
      end

      def load_for_document(doc, key)
        cache = cache_for(doc)
        return nil unless cache

        data = Infrastructure::PerfTracer.measure('cache.lookup') { cache.load_layout(key) }
        extract_pages(data)
      rescue StandardError
        nil
      end

      def save_for_document(doc, key, pages_compact)
        cache = cache_for(doc)
        return false unless cache

        payload = {
          'version' => SCHEMA_VERSION,
          'pages' => pages_compact,
        }
        cache.mutate_layouts! { |layouts| layouts[key] = payload }
      end

      def delete_for_document(doc, key)
        cache = cache_for(doc)
        return false unless cache

        cache.mutate_layouts! { |layouts| layouts.delete(key) }
      end

      def exists_for_document?(doc, key)
        cache = cache_for(doc)
        return false unless cache

        !!cache.load_layout(key)
      rescue StandardError
        false
      end

      def extract_pages(data)
        return nil unless data.is_a?(Hash)

        version = data['version'] || data[:version]
        pages = data['pages'] || data[:pages]
        return nil unless pages.is_a?(Array)
        return nil if version && version.to_i > SCHEMA_VERSION

        pages.map do |entry|
          {
            chapter_index: entry[:chapter_index] || entry['chapter_index'],
            page_in_chapter: entry[:page_in_chapter] || entry['page_in_chapter'],
            total_pages_in_chapter: entry[:total_pages_in_chapter] || entry['total_pages_in_chapter'],
            start_line: entry[:start_line] || entry['start_line'],
            end_line: entry[:end_line] || entry['end_line'],
          }
        end
      end

      def cache_for(doc)
        path = resolve_cache_path(doc)
        return nil unless path && File.exist?(path)

        EbookReader::Infrastructure::EpubCache.new(path)
      rescue EbookReader::Error, StandardError
        nil
      end
      private_class_method :cache_for

      def resolve_cache_path(doc)
        return doc.cache_path if doc.respond_to?(:cache_path) && doc.cache_path && !doc.cache_path.to_s.empty?

        if doc.respond_to?(:cache_dir) && doc.cache_dir && !doc.cache_dir.to_s.empty?
          legacy = Dir.children(doc.cache_dir).find { |name| name.end_with?(EpubCache.cache_extension) }
          return File.join(doc.cache_dir, legacy) if legacy
        end

        if doc.respond_to?(:canonical_path) && doc.canonical_path && File.exist?(doc.canonical_path)
          cache = EbookReader::Infrastructure::EpubCache.new(doc.canonical_path)
          return cache.cache_path if File.exist?(cache.cache_path)
        end

        nil
      rescue EbookReader::Error, StandardError
        nil
      end
      private_class_method :resolve_cache_path
    end
  end
end
