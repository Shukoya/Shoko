# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'

require_relative '../constants'
require_relative 'models/scanner_context'
require_relative 'epub_finder/directory_scanner'

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
        return scan_with_timeout if force_refresh

        scan_with_timeout
      rescue StandardError
        cached_files
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
        cache && cache['files'].is_a?(Array) && !cache['files'].empty?
      end

      def scan_with_timeout
        epubs = perform_scan_with_timeout
        save_and_return_epubs(epubs)
      rescue Timeout::Error
        cached_files_fallback
      end

      def perform_scan_with_timeout
        Timeout.timeout(SCAN_TIMEOUT) { perform_scan }
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

        warn "Found #{epubs.length} EPUB files" if DEBUG_MODE
        epubs
      end

      def load_cache
        return nil unless File.exist?(CACHE_FILE)

        parse_cache_file
      rescue StandardError => e
        warn "Cache load error: #{e.message}" if DEBUG_MODE
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
        File.write(CACHE_FILE, JSON.pretty_generate({
                                                      'timestamp' => Time.now.iso8601,
                                                      'files' => files || [],
                                                      'version' => VERSION,
                                                    }))
      rescue StandardError => e
        warn "Cache save error: #{e.message}" if DEBUG_MODE
      end
    end
  end
end
