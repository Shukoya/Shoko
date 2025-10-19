# frozen_string_literal: true

require 'json'
require 'time'

require_relative 'cache_paths'
require_relative 'cache_database'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Centralised persistence API for EPUB caches.
    # Responsible for talking to the SQLite database and keeping basic statistics.
    class CacheStore
      Payload = Struct.new(
        :metadata_row,
        :chapters,
        :resources,
        :layouts,
        keyword_init: true
      )
      private_constant :Payload

      def initialize(cache_root: CachePaths.reader_root, database: nil)
        @cache_root = cache_root
        @database = database || CacheDatabase.new(cache_root:)
      end

      attr_reader :database

      def fetch_payload(sha)
        result = nil
        metadata = nil
        chapters = []
        resources = []
        layouts = []

        database.with_connection do |db|
          metadata = db.get_first_row(
            <<~SQL,
              SELECT b.*, s.cache_size_bytes
              FROM books b
              LEFT JOIN stats s ON s.source_sha = b.source_sha
              WHERE b.source_sha = ?
            SQL
            [sha]
          )
          return nil unless metadata

          chapters = db.execute('SELECT * FROM chapters WHERE source_sha = ? ORDER BY position ASC', [sha])
          resources = db.execute('SELECT path, data FROM resources WHERE source_sha = ?', [sha])
          layouts = db.execute('SELECT key, version, payload_json FROM layouts WHERE source_sha = ?', [sha])
          touch_stats(db, sha, metadata['cache_size_bytes'])
        end

        result = Payload.new(
          metadata_row: metadata,
          chapters: chapters,
          resources: resources,
          layouts: layouts
        )
        result
      rescue CacheDatabase::Error, SQLite3::Exception => e
        Logger.debug('CacheStore: fetch failed', sha:, error: e.message)
        nil
      end

      def write_payload(sha:, source_path:, source_mtime:, generated_at:, serialized_book:, serialized_chapters:, serialized_resources:, serialized_layouts:)
        now = Time.now.utc.to_f
        total_resource_bytes = serialized_resources.sum { |res| res[:data].bytesize }

        database.with_connection do |db|
          db.transaction
          db.execute('DELETE FROM books WHERE source_sha = ?', [sha])
          db.execute(
            <<~SQL,
              INSERT INTO books (
                source_sha, source_path, source_mtime, payload_version, generated_at,
                title, language, authors_json, metadata_json, opf_path,
                spine_json, chapter_hrefs_json, toc_json, container_path,
                container_xml, cache_version, created_at, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
            [
              sha,
              source_path,
              source_mtime&.to_f,
              serialized_book[:payload_version],
              generated_at&.to_f,
              serialized_book[:title],
              serialized_book[:language],
              serialized_book[:authors_json],
              serialized_book[:metadata_json],
              serialized_book[:opf_path],
              serialized_book[:spine_json],
              serialized_book[:chapter_hrefs_json],
              serialized_book[:toc_json],
              serialized_book[:container_path],
              serialized_book[:container_xml],
              serialized_book[:cache_version],
              now,
              now
            ]
          )

          serialized_chapters.each do |chapter|
            db.execute(
              <<~SQL,
                INSERT INTO chapters (
                  source_sha, position, number, title, lines_json,
                  metadata_json, blocks_json, raw_content
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              SQL
              [
                sha,
                chapter[:position],
                chapter[:number],
                chapter[:title],
                chapter[:lines_json],
                chapter[:metadata_json],
                chapter[:blocks_json],
                chapter[:raw_content]
              ]
            )
          end

          serialized_resources.each do |res|
            db.execute(
              'INSERT INTO resources (source_sha, path, data) VALUES (?, ?, ?)',
              [sha, res[:path], SQLite3::Blob.new(res[:data])]
            )
          end

          db.execute('DELETE FROM layouts WHERE source_sha = ?', [sha])
          serialized_layouts.each do |key, payload|
            db.execute(
              <<~SQL,
                INSERT INTO layouts (source_sha, key, version, payload_json, updated_at)
                VALUES (?, ?, ?, ?, ?)
              SQL
              [
                sha,
                key,
                payload_version(payload),
                JSON.generate(payload),
                now
              ]
            )
          end

          db.execute(
            <<~SQL,
              INSERT INTO stats (source_sha, last_accessed, cache_size_bytes)
              VALUES (?, ?, ?)
              ON CONFLICT(source_sha) DO UPDATE SET
                last_accessed = excluded.last_accessed,
                cache_size_bytes = excluded.cache_size_bytes
            SQL
            [sha, now, total_resource_bytes]
          )

          db.commit
        end
        true
      rescue CacheDatabase::Error, SQLite3::Exception => e
        Logger.debug('CacheStore: write failed', sha:, error: e.message)
        false
      end

      def delete_payload(sha)
        database.with_connection do |db|
          db.execute('DELETE FROM books WHERE source_sha = ?', [sha])
        end
      rescue CacheDatabase::Error, SQLite3::Exception => e
        Logger.debug('CacheStore: delete failed', sha:, error: e.message)
        false
      end

      def load_layout(sha, key)
        row = nil
        database.with_connection do |db|
          row = db.get_first_row(
            'SELECT payload_json FROM layouts WHERE source_sha = ? AND key = ?',
            [sha, key]
          )
        end
        return nil unless row

        JSON.parse(row['payload_json'])
      rescue CacheDatabase::Error, SQLite3::Exception, JSON::ParserError => e
        Logger.debug('CacheStore: layout load failed', sha:, key:, error: e.message)
        nil
      end

      def fetch_layouts(sha)
        layouts = {}
        database.with_connection do |db|
          rows = db.execute('SELECT key, payload_json FROM layouts WHERE source_sha = ?', [sha])
          rows.each do |row|
            layouts[row['key']] = JSON.parse(row['payload_json'])
          end
        end
        layouts
      rescue CacheDatabase::Error, SQLite3::Exception, JSON::ParserError => e
        Logger.debug('CacheStore: layouts fetch failed', sha:, error: e.message)
        {}
      end

      def mutate_layouts(sha)
        layouts = {}
        database.with_connection do |db|
          rows = db.execute('SELECT key, payload_json FROM layouts WHERE source_sha = ?', [sha])
          rows.each do |row|
            layouts[row['key']] = JSON.parse(row['payload_json'])
          end
        end

        yield layouts

        normalized = layouts.each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = value
        end
        serialized = normalized.transform_values { |value| JSON.generate(value) }
        database.with_connection do |db|
          db.transaction
          db.execute('DELETE FROM layouts WHERE source_sha = ?', [sha])
          now = Time.now.utc.to_f
          serialized.each do |key, payload_json|
            db.execute(
              'INSERT INTO layouts (source_sha, key, version, payload_json, updated_at) VALUES (?, ?, ?, ?, ?)',
              [sha, key, payload_version(normalized[key]), payload_json, now]
            )
          end
          db.commit
        end
        true
      rescue CacheDatabase::Error, SQLite3::Exception, JSON::ParserError => e
        Logger.debug('CacheStore: mutate layouts failed', sha:, error: e.message)
        false
      end

      def list_books
        database.with_connection do |db|
          db.execute(<<~SQL)
            SELECT b.*, s.cache_size_bytes
            FROM books b
            LEFT JOIN stats s ON s.source_sha = b.source_sha
            ORDER BY b.updated_at DESC
          SQL
        end
      rescue CacheDatabase::Error, SQLite3::Exception => e
        Logger.debug('CacheStore: list_books failed', error: e.message)
        []
      end

      def close
        database.close_all
      end

      private

      def payload_version(payload)
        value = payload['version'] || payload[:version]
        value ? value.to_i : 1
      end

      def touch_stats(db, sha, cache_size_bytes)
        now = Time.now.utc.to_f
        db.execute(
          <<~SQL,
            INSERT INTO stats (source_sha, last_accessed, cache_size_bytes)
            VALUES (?, ?, COALESCE(?, 0))
            ON CONFLICT(source_sha) DO UPDATE SET last_accessed = excluded.last_accessed
          SQL
          [sha, now, cache_size_bytes]
        )
      end
    end
  end
end
