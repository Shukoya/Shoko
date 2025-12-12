# frozen_string_literal: true

require 'digest'
require 'time'

require_relative '../domain/models/chapter'
require_relative '../domain/models/toc_entry'
require_relative '../domain/models/content_block'
require_relative '../errors'
require_relative 'cache_paths'
require_relative 'marshal_cache_store'
require_relative 'cache_pointer_manager'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Marshal-backed cache for imported EPUB data and derived pagination layouts.
    # Pointer files keep lightweight `.cache` discovery while the bulk payload
    # lives in `.marshal` blobs.
    class EpubCache
      CACHE_VERSION   = 2
      CACHE_EXTENSION = '.cache'
      SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

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

      class << self
        def cache_extension = CACHE_EXTENSION

        def cache_file?(path)
          File.file?(path) && File.extname(path).casecmp(CACHE_EXTENSION).zero?
        end

        def cache_path_for_sha(sha, cache_root: CachePaths.reader_root)
          normalized = sha.to_s.strip
          return nil unless normalized.match?(SHA256_HEX_PATTERN)

          File.join(cache_root, "#{normalized.downcase}#{CACHE_EXTENSION}")
        end
      end

      attr_reader :cache_path, :source_path

      def initialize(path, cache_root: CachePaths.reader_root, store: nil)
        @cache_root = cache_root
        @cache_store = store || MarshalCacheStore.new(cache_root: @cache_root)
        @raw_path = File.expand_path(path)
        @payload_cache = nil
        @layout_cache = {}
        @pointer_metadata = nil
        setup_source_reference
      end

      # Load pointer payload without validating source. Used by cached-library
      # direct opens.
      def read_cache(strict: false)
        payload = load_payload
        return nil unless payload

        return payload unless strict
        payload_valid?(payload) ? payload : invalidate_and_nil
      rescue EbookReader::CacheLoadError
        nil
      end

      # Load payload and ensure it matches the original EPUB file.
      def load_for_source(strict: false)
        payload = load_payload
        return nil unless payload

        if payload_valid?(payload) && payload_matches_source?(payload, strict:)
          payload
        else
          invalidate_and_nil
        end
      end

      def write_book!(book_data)
        ensure_sha!
        generated_at = Time.now.utc
        source_mtime = safe_mtime(@source_path)

        persist_payload(@source_sha, @source_path, source_mtime, generated_at, book_data, {})

        payload = CachePayload.new(
          version: CACHE_VERSION,
          source_sha256: @source_sha,
          source_path: @source_path,
          source_mtime: source_mtime,
          generated_at: generated_at,
          book: book_data,
          layouts: {}
        )
        @payload_cache = payload
        @layout_cache = {}
        payload
      rescue StandardError => e
        Logger.debug('EpubCache: failed to write cache', path: @cache_path, error: e.message)
        nil
      end

      def load_layout(key)
        key_str = key.to_s
        if @layout_cache.key?(key_str)
          return deep_dup(@layout_cache[key_str])
        end

        payload = @cache_store.load_layout(@source_sha, key_str)
        return nil unless payload

        cache_layout!(key_str, payload)
        deep_dup(payload)
      rescue StandardError
        nil
      end

      def mutate_layouts!
        ensure_sha!
        mutated = nil
        success = @cache_store.mutate_layouts(@source_sha) do |layouts|
          mutated = {}
          yield layouts
          layouts.each { |k, v| mutated[k.to_s] = deep_dup(v) }
        end
        if success
          @layout_cache = mutated || {}
          if @payload_cache
            @payload_cache.layouts = @layout_cache.transform_values { |value| deep_dup(value) }
          end
        end
        success
      rescue StandardError => e
        Logger.debug('EpubCache: failed to update layouts', path: @cache_path, error: e.message)
        false
      end

      def invalidate!
        ensure_sha!
        @cache_store.delete_payload(@source_sha) if @source_sha
        FileUtils.rm_f(@cache_path) if @cache_path && File.exist?(@cache_path)
      ensure
        @payload_cache = nil
        @layout_cache = {}
        @pointer_metadata = nil
      end

      def cache_file?
        @source_type == :cache_pointer
      end

      def sha256
        ensure_sha!
        @source_sha
      end

      def layout_keys
        ensure_sha!
        keys = @cache_store.fetch_layouts(@source_sha).keys
        keys |= @layout_cache.keys
        keys
      rescue StandardError
        []
      end

      private

      def setup_source_reference
        if self.class.cache_file?(@raw_path)
          @cache_path = @raw_path
          @pointer_manager = CachePointerManager.new(@cache_path)
          pointer = @pointer_manager.read
          if pointer
            @source_type = :cache_pointer
            @pointer_metadata = pointer
            @source_sha = pointer['sha256']
            @source_path = pointer['source_path']
          else
            raise EbookReader::CacheLoadError.new(@raw_path, 'invalid pointer file')
          end
        else
          raise EbookReader::FileNotFoundError, @raw_path unless File.file?(@raw_path)

          @source_type = :epub
          @source_path = @raw_path
          @source_sha = Digest::SHA256.file(@source_path).hexdigest
          @cache_path = self.class.cache_path_for_sha(@source_sha, cache_root: @cache_root)
          raise EbookReader::CacheLoadError.new(@raw_path, 'invalid sha256 digest') unless @cache_path
          @pointer_manager = CachePointerManager.new(@cache_path)
          @pointer_metadata = @pointer_manager.read
        end
      end

      def ensure_sha!
        return if @source_sha

        if @source_type == :epub
          @source_sha = Digest::SHA256.file(@source_path).hexdigest
        elsif @pointer_metadata
          @source_sha = @pointer_metadata['sha256']
        end
      end

      def load_payload
        return @payload_cache if @payload_cache

        ensure_sha!
        payload = load_payload_from_store(@source_sha)

        if payload
          @payload_cache = payload
          layouts = payload.layouts || {}
          @layout_cache = layouts.transform_values { |value| deep_dup(value) }
        end
        payload
      end

      def load_payload_from_store(sha)
        return nil unless sha

        raw = @cache_store.fetch_payload(sha)
        return nil unless raw

        ensure_pointer_from_metadata(raw.metadata_row)
        Serializer.build_payload_from_store(raw)
      rescue StandardError => e
        Logger.debug('EpubCache: failed to load cache', sha:, error: e.message)
        nil
      end

      def persist_payload(sha, source_path, source_mtime, generated_at, book_data, layouts_hash)
        engine = cache_engine
        pointer_metadata = {
          'format' => CachePointerManager::POINTER_FORMAT,
          'version' => CachePointerManager::POINTER_VERSION,
          'sha256' => sha,
          'source_path' => source_path,
          'generated_at' => (generated_at || Time.now.utc).iso8601,
          'engine' => engine
        }

        serialized = Serializer.serialize(book_data, json: false)
        layouts_serialized = Serializer.serialize_layouts(layouts_hash)

        success = @cache_store.write_payload(
          sha: sha,
          source_path: source_path,
          source_mtime: source_mtime,
          generated_at: generated_at,
          serialized_book: serialized[:book],
          serialized_chapters: serialized[:chapters],
          serialized_resources: serialized[:resources],
          serialized_layouts: layouts_serialized
        )
        return unless success

        @pointer_manager ||= CachePointerManager.new(@cache_path)
        @pointer_manager.write(pointer_metadata)
        @pointer_metadata = pointer_metadata
        @source_type = :cache_pointer
      end

      def payload_valid?(payload)
        payload.is_a?(CachePayload) &&
          payload.version.to_i == CACHE_VERSION &&
          payload.book.is_a?(BookData)
      end

      def payload_matches_source?(payload, strict:)
        return true if cache_file? && !payload.source_path

        ensure_sha!
        return false unless payload.source_sha256 == @source_sha

        source_mtime = safe_mtime(@source_path)
        payload_mtime = payload.source_mtime
        return true unless source_mtime && payload_mtime

        tolerance = strict ? 1e-3 : 1.0
        (source_mtime.to_f - payload_mtime.to_f).abs <= tolerance
      end

      def safe_mtime(path)
        File.mtime(path)&.utc
      rescue StandardError
        nil
      end

      def cache_layout!(key, payload)
        @layout_cache ||= {}
        @layout_cache[key] = deep_dup(payload)
        if @payload_cache
          @payload_cache.layouts ||= {}
          @payload_cache.layouts[key] = deep_dup(payload)
        end
      end

      def deep_dup(obj)
        Marshal.load(Marshal.dump(obj))
      end

      def invalidate_and_nil
        invalidate!
        nil
      end

      def ensure_pointer_from_metadata(record)
        return unless record
        ensure_sha!
        record_engine = Serializer.value_for(record, :engine) || cache_engine
        pointer_metadata = {
          'format' => CachePointerManager::POINTER_FORMAT,
          'version' => CachePointerManager::POINTER_VERSION,
          'sha256' => Serializer.value_for(record, :source_sha),
          'source_path' => Serializer.value_for(record, :source_path),
          'generated_at' => Serializer.coerce_time(Serializer.value_for(record, :generated_at))&.iso8601 || Time.now.utc.iso8601,
          'engine' => record_engine
        }

        current = @pointer_manager&.read
        return if current && current['sha256'] == pointer_metadata['sha256']

        @pointer_manager ||= CachePointerManager.new(@cache_path)
        @pointer_manager.write(pointer_metadata)
        @pointer_metadata = pointer_metadata
        @source_type = :cache_pointer
      end

      def cache_engine
        engine = @cache_store&.respond_to?(:engine) ? @cache_store.engine : nil
        engine || MarshalCacheStore::ENGINE
      rescue StandardError
        MarshalCacheStore::ENGINE
      end

      module Serializer
        module_function

        def serialize(book_data, json: false)
          {
            book: serialize_book(book_data, json:),
            chapters: serialize_chapters(book_data.chapters, json:),
            resources: serialize_resources(book_data.resources)
          }
        end

        def serialize_layouts(layouts_hash)
          result = {}
          Array(layouts_hash).each do |key, payload|
            result[key.to_s] = payload
          end
          result
        end

        def serialize_book(book, json: true)
          authors = Array(book.authors)
          metadata = book.metadata || {}
          spine = Array(book.spine)
          hrefs = Array(book.chapter_hrefs)
          toc = Array(book.toc_entries).map { |entry| serialize_toc_entry(entry, json:) }
          authors_field = json ? JSON.generate(authors) : authors
          metadata_field = json ? JSON.generate(metadata) : metadata
          spine_field = json ? JSON.generate(spine) : spine
          hrefs_field = json ? JSON.generate(hrefs) : hrefs
          toc_field = json ? JSON.generate(toc) : toc
          {
            payload_version: CACHE_VERSION,
            cache_version: CACHE_VERSION,
            title: book.title,
            language: book.language,
            authors_json: authors_field,
            metadata_json: metadata_field,
            opf_path: book.opf_path,
            spine_json: spine_field,
            chapter_hrefs_json: hrefs_field,
            toc_json: toc_field,
            container_path: book.container_path,
            container_xml: book.container_xml.to_s
          }
        end

        def serialize_chapters(chapters, json: true)
          Array(chapters).each_with_index.map do |chapter, idx|
            lines = Array(chapter.lines)
            metadata = chapter.metadata || {}
            blocks = serialize_blocks(chapter.blocks, json:)
            lines_field = json ? JSON.generate(lines) : lines
            metadata_field = json ? JSON.generate(metadata) : metadata
            blocks_field = json ? JSON.generate(blocks) : blocks
            {
              position: idx,
              number: chapter.number,
              title: chapter.title,
              lines_json: lines_field,
              metadata_json: metadata_field,
              blocks_json: blocks_field,
              raw_content: chapter.raw_content
            }
          end
        end

        def serialize_blocks(blocks, json: true)
          Array(blocks).map do |block|
            {
              type: value_for(block, :type),
              level: value_for(block, :level),
              metadata: value_for(block, :metadata),
              segments: Array(value_for(block, :segments)).map do |segment|
                {
                  text: value_for(segment, :text),
                  styles: value_for(segment, :styles)
                }
              end
            }
          end
        end

        def serialize_resources(resources)
          return [] unless resources

          resources.map do |path, data|
            data = String(data).dup
            data.force_encoding(Encoding::BINARY)
            {
              path: path.to_s,
              data: data
            }
          end
        end

        def serialize_toc_entry(entry, json: true)
          {
            title: value_for(entry, :title),
            href: value_for(entry, :href),
            level: value_for(entry, :level),
            chapter_index: value_for(entry, :chapter_index),
            navigable: value_for(entry, :navigable)
          }
        end

        def build_payload_from_store(raw_payload)
          metadata = raw_payload.metadata_row || {}
          book = deserialize_book(metadata, raw_payload.chapters, raw_payload.resources)
          layouts = normalize_layouts(raw_payload.layouts)

          CachePayload.new(
            version: value_for(metadata, :cache_version) || CACHE_VERSION,
            source_sha256: value_for(metadata, :source_sha),
            source_path: value_for(metadata, :source_path),
            source_mtime: coerce_time(value_for(metadata, :source_mtime)),
            generated_at: coerce_time(value_for(metadata, :generated_at)),
            book: book,
            layouts: layouts
          )
        end

        def deserialize_book(book_row, chapter_rows, resource_rows)
          authors = value_for(book_row, :authors_json)
          authors = JSON.parse(authors || '[]') if authors.is_a?(String)
          metadata = value_for(book_row, :metadata_json)
          metadata = JSON.parse(metadata || '{}') if metadata.is_a?(String)
          spine = value_for(book_row, :spine_json)
          spine = JSON.parse(spine || '[]') if spine.is_a?(String)
          hrefs = value_for(book_row, :chapter_hrefs_json)
          hrefs = JSON.parse(hrefs || '[]') if hrefs.is_a?(String)
          toc = value_for(book_row, :toc_json)
          toc = JSON.parse(toc || '[]') if toc.is_a?(String)
          BookData.new(
            title: value_for(book_row, :title),
            language: value_for(book_row, :language),
            authors: Array(authors),
            chapters: deserialize_chapters(chapter_rows),
            toc_entries: deserialize_toc(toc),
            opf_path: value_for(book_row, :opf_path),
            spine: Array(spine),
            chapter_hrefs: Array(hrefs),
            resources: deserialize_resources(resource_rows),
            metadata: metadata || {},
            container_path: value_for(book_row, :container_path),
            container_xml: value_for(book_row, :container_xml)
          )
        end

        def deserialize_chapters(rows)
          Array(rows).map do |row|
            lines = value_for(row, :lines_json)
            lines = JSON.parse(lines || '[]') if lines.is_a?(String)
            lines = [] unless lines.is_a?(Array)
            metadata = value_for(row, :metadata_json)
            metadata = JSON.parse(metadata || '{}') if metadata.is_a?(String)
            EbookReader::Domain::Models::Chapter.new(
              number: value_for(row, :number),
              title: value_for(row, :title),
              lines: lines,
              metadata: metadata || {},
              blocks: deserialize_blocks(value_for(row, :blocks_json)),
              raw_content: value_for(row, :raw_content)
            )
          end
        end

        def deserialize_blocks(json)
          return nil unless json

          data = json.is_a?(String) ? JSON.parse(json) : json
          return nil unless data.is_a?(Array)

          data.map do |block|
            EbookReader::Domain::Models::ContentBlock.new(
              type: value_for(block, :type),
              level: value_for(block, :level),
              metadata: value_for(block, :metadata),
              segments: Array(value_for(block, :segments)).map do |seg|
                EbookReader::Domain::Models::TextSegment.new(
                  text: value_for(seg, :text),
                  styles: value_for(seg, :styles) || {}
                )
              end
            )
          end
        end

        def deserialize_toc(json)
          data = json.is_a?(String) ? JSON.parse(json || '[]') : json
          Array(data).map do |entry|
            navigable = value_for(entry, :navigable)
            navigable = true if navigable.nil?
            EbookReader::Domain::Models::TOCEntry.new(
              title: value_for(entry, :title),
              href: value_for(entry, :href),
              level: value_for(entry, :level),
              chapter_index: value_for(entry, :chapter_index),
              navigable: navigable
            )
          end
        end

        def deserialize_resources(rows)
          Array(rows).each_with_object({}) do |row, acc|
            data = value_for(row, :data)
            data = data.to_s.dup
            data.force_encoding(Encoding::BINARY)
            path = value_for(row, :path)
            acc[path] = data if path
          end
        end

        def coerce_time(raw)
          return raw if raw.is_a?(Time)
          return nil unless raw

          Time.at(raw.to_f).utc
        rescue StandardError
          nil
        end

        def normalize_layouts(raw_layouts)
          return {} unless raw_layouts

          if raw_layouts.is_a?(Hash)
            raw_layouts.each_with_object({}) do |(key, payload), acc|
              normalized = normalize_layout_payload(payload)
              acc[key.to_s] = normalized if normalized
            end
          else
            Array(raw_layouts).each_with_object({}) do |row, acc|
              key = value_for(row, :key)
              payload = value_for(row, :payload_json) || value_for(row, :payload)
              normalized = normalize_layout_payload(payload)
              acc[key.to_s] = normalized if key && normalized
            end
          end
        end

        def normalize_layout_payload(payload)
          return nil unless payload

          payload.is_a?(String) ? JSON.parse(payload) : payload
        rescue JSON::ParserError
          nil
        end

        def value_for(obj, key)
          if obj.respond_to?(key)
            obj.public_send(key)
          elsif obj.respond_to?(:[])
            obj[key] || obj[key.to_s]
          end
        end
      end
    end
  end
end
