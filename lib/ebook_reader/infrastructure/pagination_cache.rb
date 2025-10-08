# frozen_string_literal: true

require 'json'
require_relative '../serializers'
require_relative 'atomic_file_writer'

module EbookReader
  module Infrastructure
    # Persists dynamic pagination (per-layout) into the book's cache directory.
    # Stores compact page entries (no text): chapter_index, page_in_chapter,
    # total_pages_in_chapter, start_line, end_line.
    module PaginationCache
      module_function

      SCHEMA_VERSION = 1

      def layout_key(width, height, view_mode, line_spacing)
        "#{width}x#{height}_#{view_mode}_#{line_spacing}"
      end

      def load_for_document(doc, key)
        dir = resolve_cache_dir(doc)
        return nil unless dir

        path, serializer = locate(dir, key)
        return nil unless path

        data = serializer.load_file(path)
        pages = extract_pages(data)
        return nil unless pages

        pages.map do |h|
          {
            chapter_index: h['chapter_index'] || h[:chapter_index],
            page_in_chapter: h['page_in_chapter'] || h[:page_in_chapter],
            total_pages_in_chapter: h['total_pages_in_chapter'] || h[:total_pages_in_chapter],
            start_line: h['start_line'] || h[:start_line],
            end_line: h['end_line'] || h[:end_line],
          }
        end
      rescue StandardError
        nil
      end

      def save_for_document(doc, key, pages_compact)
        dir = resolve_cache_dir(doc)
        return false unless dir

        serializer = select_serializer
        final = File.join(dir, 'pagination', "#{key}.#{serializer.ext}")
        payload = {
          'version' => SCHEMA_VERSION,
          'pages' => pages_compact,
        }
        AtomicFileWriter.write_using(final, binary: serializer.binary?) do |io|
          serializer.dump_to_io(io, payload)
        end
        true
      rescue StandardError
        false
      end

      def resolve_cache_dir(doc)
        # Prefer cache_dir if document exposes it (cached open)
        return doc.cache_dir if doc.respond_to?(:cache_dir) && doc.cache_dir && !doc.cache_dir.to_s.empty?

        # Fallback: compute cache dir from epub path via EpubCache
        if doc.respond_to?(:canonical_path) && doc.canonical_path && File.exist?(doc.canonical_path)
          cache = EbookReader::Infrastructure::EpubCache.new(doc.canonical_path)
          return cache.cache_dir
        end
        nil
      rescue StandardError
        nil
      end

      def locate(dir, key)
        mp = File.join(dir, 'pagination', "#{key}.msgpack")
        js = File.join(dir, 'pagination', "#{key}.json")
        if File.exist?(mp) && SerializerSupport.msgpack_available?
          [mp, MessagePackSerializer.new]
        elsif File.exist?(js)
          [js, JSONSerializer.new]
        else
          [nil, nil]
        end
      end

      def exists_for_document?(doc, key)
        dir = resolve_cache_dir(doc)
        return false unless dir

        base = File.join(dir, 'pagination', key)
        mp = "#{base}.msgpack"
        js = "#{base}.json"
        File.exist?(mp) || File.exist?(js)
      rescue StandardError
        false
      end

      def select_serializer
        SerializerSupport.msgpack_available? ? MessagePackSerializer.new : JSONSerializer.new
      end

      # Serializers are defined in lib/ebook_reader/serializers.rb (outside infra path for test coverage isolation)

      def delete_for_document(doc, key)
        dir = resolve_cache_dir(doc)
        return false unless dir

        base = File.join(dir, 'pagination', key)
        mp = "#{base}.msgpack"
        js = "#{base}.json"
        removed = false
        [mp, js].each do |p|
          next unless File.exist?(p)

          File.delete(p)
          removed = true
        end
        removed
      rescue StandardError
        false
      end

      def extract_pages(data)
        case data
        when Hash
          version = data['version'] || data[:version]
          pages = data['pages'] || data[:pages]
          return nil unless version.nil? || version.to_i <= SCHEMA_VERSION
          return nil unless pages.is_a?(Array)

          pages
        when Array
          data
        end
      end
    end
  end
end
