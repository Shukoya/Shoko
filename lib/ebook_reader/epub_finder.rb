# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'
require 'set'

require_relative 'models/scanner_context'
require_relative 'epub_finder/directory_scanner'
require_relative 'infrastructure/atomic_file_writer'

module EbookReader
  # EPUB file finder with robust error handling
  class EPUBFinder
    SCAN_TIMEOUT = Constants::SCAN_TIMEOUT
    MAX_DEPTH = Constants::MAX_DEPTH
    MAX_FILES = Constants::MAX_FILES
    CONFIG_DIR = File.expand_path('~/.config/reader')
    CACHE_FILE = File.join(CONFIG_DIR, 'epub_cache.json')
    DEBUG_MODE = ARGV.include?('--debug') || ENV.fetch('DEBUG', nil)

    class << self
      def scan_system(force_refresh: false)
        return cached_files unless force_refresh || cache_expired?

        scan_with_timeout
      end

      def clear_cache
        FileUtils.rm_f(CACHE_FILE)
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
        return false unless cache
        files = cache['files']
        ts = cache['timestamp']
        files.is_a?(Array) && !files.empty? && ts && !cache_expired?(ts)
      end

      def cache_expired?(timestamp = nil)
        return true unless timestamp

        Time.now - Time.parse(timestamp) >= Constants::CACHE_DURATION
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

      def skip_directory?(path)
        DirectoryScanner.new(nil).send(:skip_directory?, path)
      end

      def epub_file?(path)
        DirectoryScanner.new(nil).send(:epub_file?, path)
      end

      def safe_directory_exists?(dir)
        DirectoryScanner.new(nil).send(:safe_directory_exists?, dir)
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
        return nil unless File.exist?(CACHE_FILE)

        parse_cache_file
      rescue StandardError => e
        warn_debug "Cache load error: #{e.message}"
        delete_corrupted_cache
        nil
      end

      def parse_cache_file
        data = File.read(CACHE_FILE)
        json = JSON.parse(data)
        json if json.is_a?(Hash)
      end

      def delete_corrupted_cache
        File.delete(CACHE_FILE)
      rescue StandardError
        nil
      end

      def save_cache(files)
        FileUtils.mkdir_p(CONFIG_DIR)
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
