# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'

require_relative 'models/scanner_context'
require_relative 'epub_finder/directory_scanner'
require_relative 'infrastructure/atomic_file_writer'
require_relative 'infrastructure/config_paths'

module EbookReader
  # EPUB file finder with robust error handling
  class EPUBFinder
    SCAN_TIMEOUT = Constants::SCAN_TIMEOUT
    MAX_DEPTH = Constants::MAX_DEPTH
    MAX_FILES = Constants::MAX_FILES
    CONFIG_DIR = Infrastructure::ConfigPaths.reader_root
    LEGACY_CONFIG_DIR = Infrastructure::ConfigPaths.legacy_reader_root
    CACHE_FILE = File.join(CONFIG_DIR, 'epub_cache.json')
    LEGACY_CACHE_FILE = File.join(LEGACY_CONFIG_DIR, 'epub_cache.json')
    DEBUG_MODE = ARGV.include?('--debug') || ENV.fetch('DEBUG', nil)

    class << self
      def scan_system(force_refresh: false)
        cache = load_cache
        return cache['files'] if !force_refresh && cache_valid?(cache)

        scan_with_timeout
      end

      def clear_cache
        FileUtils.rm_f(CACHE_FILE)
        FileUtils.rm_f(LEGACY_CACHE_FILE) if LEGACY_CACHE_FILE != CACHE_FILE
      rescue StandardError
        nil
      end

      private

      def cached_files
        cache = load_cache
        return [] unless cache_valid?(cache)

        cache['files']
      end

      def cache_valid?(cache)
        return false unless cache.is_a?(Hash)

        files = cache['files']
        ts = cache['timestamp']
        files.is_a?(Array) && ts && !cache_expired?(ts)
      end

      def cache_expired?(timestamp = nil)
        ts = timestamp.to_s.strip
        return true if ts.empty?

        Time.now - Time.parse(ts) >= Constants::CACHE_DURATION
      rescue StandardError
        true
      end

      def scan_with_timeout
        epubs = []
        epubs = perform_scan_with_timeout
      rescue Timeout::Error
        handle_timeout_error(epubs)
      rescue StandardError
        epubs = cached_files_fallback
      ensure
        save_and_return_epubs(epubs)
      end

      def perform_scan_with_timeout
        Timeout.timeout(SCAN_TIMEOUT) { perform_scan }
      end

      def handle_timeout_error(epubs)
        save_cache(epubs) unless epubs.empty?
        epubs
      end

      def save_and_return_epubs(epubs)
        save_cache(epubs)
        epubs
      end

      def cached_files_fallback
        cache = load_cache
        cache && cache['files'] ? cache['files'] : []
      end

      def perform_scan
        epubs = []
        context = Models::ScannerContext.new(
          epubs: epubs,
          visited_paths: Set.new,
          depth: 0
        )

        scanner = DirectoryScanner.new(context)
        scanner.scan_all_directories

        warn_debug "Found #{epubs.length} EPUB files"
        epubs
      end

      def load_cache
        [CACHE_FILE, LEGACY_CACHE_FILE].uniq.each do |path|
          next unless File.exist?(path)

          cache = begin
            parse_cache_file(path)
          rescue StandardError => e
            warn_debug "Cache load error: #{e.message}"
            delete_cache_file(path)
            nil
          end
          next unless cache

          if path == LEGACY_CACHE_FILE && CACHE_FILE != LEGACY_CACHE_FILE && !File.exist?(CACHE_FILE)
            migrate_cache!(cache)
          end

          return cache
        end

        nil
      end

      def parse_cache_file(path)
        data = File.read(path)
        json = JSON.parse(data)
        json if json.is_a?(Hash)
      end

      def delete_cache_file(path)
        File.delete(path)
      rescue StandardError
        nil
      end

      def migrate_cache!(cache)
        return unless cache.is_a?(Hash)

        FileUtils.mkdir_p(File.dirname(CACHE_FILE))
        payload = JSON.pretty_generate({
                                         'timestamp' => cache['timestamp'],
                                         'files' => cache['files'] || [],
                                         'version' => cache['version'] || VERSION,
                                       })
        Infrastructure::AtomicFileWriter.write(CACHE_FILE, payload)
      rescue StandardError => e
        warn_debug "Cache migration error: #{e.message}"
      end

      def save_cache(files)
        FileUtils.mkdir_p(File.dirname(CACHE_FILE))
        payload = JSON.pretty_generate({
                                         'timestamp' => Time.now.iso8601,
                                         'files' => files || [],
                                         'version' => VERSION,
                                       })
        Infrastructure::AtomicFileWriter.write(CACHE_FILE, payload)
      rescue StandardError => e
        warn_debug "Cache save error: #{e.message}"
      end

      def debug? = !!DEBUG_MODE

      def warn_debug(msg)
        warn msg if debug?
      end
    end
  end
end
