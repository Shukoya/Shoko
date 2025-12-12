# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative 'infrastructure/atomic_file_writer'
require_relative 'infrastructure/config_paths'

module EbookReader
  # Manages a list of recently opened files.
  class RecentFiles
    CONFIG_DIR = Infrastructure::ConfigPaths.reader_root
    LEGACY_CONFIG_DIR = Infrastructure::ConfigPaths.legacy_reader_root
    RECENT_FILE = File.join(CONFIG_DIR, 'recent.json')
    LEGACY_RECENT_FILE = File.join(LEGACY_CONFIG_DIR, 'recent.json')
    MAX_RECENT_FILES = 10

    class << self
      # Adds a file path to the top of the recent files list.
      #
      # @param path [String] The path to the file to add.
      def add(path)
        recent_files = load.reject { |file| file['path'] == path }

        label = File.basename(path, File.extname(path)).tr('_-', ' ')

        new_entry = {
          'path' => path,
          'name' => label,
          'accessed' => Time.now.iso8601,
        }

        save([new_entry, *recent_files].first(MAX_RECENT_FILES))
      end

      # Loads the list of recent files from disk.
      #
      # @return [Array<Hash>] An array of recent file entries.
      def load
        file = if File.exist?(RECENT_FILE)
                 RECENT_FILE
               elsif File.exist?(LEGACY_RECENT_FILE)
                 LEGACY_RECENT_FILE
               end
        return [] unless file

        JSON.parse(File.read(file))
      rescue JSON::ParserError, Errno::ENOENT
        []
      end

      # Clears the recent files list by removing the recent file.
      def clear
        FileUtils.rm_f(RECENT_FILE)
        FileUtils.rm_f(LEGACY_RECENT_FILE) if LEGACY_RECENT_FILE != RECENT_FILE
      rescue Errno::EACCES, Errno::ENOENT
        # Ignore errors
      end

      private

      # Saves the list of recent files to disk.
      #
      # @param recent [Array<Hash>] The list of recent files to save.
      def save(recent)
        FileUtils.mkdir_p(File.dirname(RECENT_FILE))
        payload = JSON.pretty_generate(recent)
        EbookReader::Infrastructure::AtomicFileWriter.write(RECENT_FILE, payload)

        # Best-effort migration when XDG paths differ.
        if LEGACY_RECENT_FILE != RECENT_FILE && File.exist?(LEGACY_RECENT_FILE)
          FileUtils.rm_f(LEGACY_RECENT_FILE)
        end
      rescue Errno::EACCES, Errno::ENOENT
        # Silently ignore file system errors, as this is not a critical feature.
      end
    end
  end
end
