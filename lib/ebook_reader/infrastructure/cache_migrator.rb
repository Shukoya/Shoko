# frozen_string_literal: true

require_relative 'cache_paths'
require_relative 'cache_database'
require_relative 'logger'

module EbookReader
  module Infrastructure
    # Lightweight migration runner for cache.sqlite3
    class CacheMigrator
      Migration = Struct.new(:version, :name, :block, keyword_init: true)
      private_constant :Migration

      def initialize(database:)
        @database = database
        @migrations = []
      end

      attr_reader :migrations

      def register(version, name, &block)
        migrations << Migration.new(version:, name:, block:)
        migrations.sort_by!(&:version)
      end

      def migrate!(connection)
        current = connection.get_first_value('PRAGMA user_version').to_i
        target = migrations.last&.version || current
        return if current >= target

        migrations.each do |migration|
          next unless migration.version.positive?
          next unless migration.version > current

          Logger.debug('CacheMigrator: applying migration', version: migration.version,
                                                          name: migration.name)
          connection.transaction
          migration.block.call(connection)
          connection.execute("PRAGMA user_version = #{migration.version}")
          connection.commit
        rescue StandardError => e
          Logger.debug('CacheMigrator: migration failed', version: migration.version, error: e.message)
          connection.rollback
          raise CacheDatabase::Error, e.message
        end
      end

      private

      attr_reader :database
    end
  end
end
