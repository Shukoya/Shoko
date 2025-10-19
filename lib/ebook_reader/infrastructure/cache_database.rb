# frozen_string_literal: true

require 'fileutils'
require 'monitor'
require 'sqlite3'

require_relative 'cache_paths'
require_relative 'logger'
require_relative 'cache_migrator'

module EbookReader
  module Infrastructure
    # Manages the SQLite database used for book caches.
    # Provides schema migrations, per-thread connections, and helper execution methods.
    class CacheDatabase
      DB_FILENAME = 'cache.sqlite3'
      SCHEMA_VERSION = 1

      class Error < StandardError; end

      def initialize(cache_root: CachePaths.reader_root)
        @cache_root = cache_root
        @db_path = File.join(@cache_root, DB_FILENAME)
        @monitor = Monitor.new
        @connections = {}
        @pid = Process.pid
        ensure_root_directory
        setup_migrator
      end

      def path
        @db_path
      end

      def with_connection
        conn = connection_for_thread
        yield conn
      rescue SQLite3::Exception => e
        raise Error, e.message
      end

      def pragma(name)
        with_connection { |db| db.get_first_value("PRAGMA #{name}") }
      end

      def vacuum
        with_connection { |db| db.execute('VACUUM') }
      end

      def close_all
        @monitor.synchronize do
          @connections.each_value do |conn|
            begin
              conn.close
            rescue SQLite3::Exception
              # ignore close failures
            end
          end
          @connections.clear
        end
      end

      private

      def ensure_root_directory
        FileUtils.mkdir_p(@cache_root)
      rescue StandardError => e
        raise Error, "failed to create cache directory: #{e.message}"
      end

      def connection_for_thread
        reset_if_forked!

        thread_key = Thread.current.object_id
        @monitor.synchronize do
          return @connections[thread_key] if @connections.key?(thread_key)

          conn = SQLite3::Database.new(@db_path)
          configure_connection(conn)
          migrate!(conn)
          @connections[thread_key] = conn
        end
      end

      def reset_if_forked!
        return if @pid == Process.pid

        close_all
        @pid = Process.pid
      end

      def configure_connection(conn)
        conn.busy_timeout = 2000
        conn.results_as_hash = true
        conn.type_translation = false if conn.respond_to?(:type_translation=)
        conn.execute('PRAGMA journal_mode = WAL')
        conn.execute('PRAGMA foreign_keys = ON')
      rescue SQLite3::Exception => e
        Logger.debug('CacheDatabase: failed to configure connection', error: e.message)
        raise Error, e.message
      end

      def migrate!(conn)
        migrator.migrate!(conn)
      end

      def setup_migrator
        @migrator = CacheMigrator.new(database: self)
        register_builtin_migrations
      end

      def migrator
        @migrator
      end

      def register_builtin_migrations
        migrator.register(1, 'initial schema') do |conn|
          path = File.expand_path('../../../db/cache_migrations/001_initial_schema.sql', __dir__)
          sql = File.read(path)
          conn.execute_batch(sql)
        end
      end
    end
  end
end
