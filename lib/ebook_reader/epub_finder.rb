# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'

require_relative 'models/scanner_context'

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
        cache && cache['files'].is_a?(Array) &&
          !cache['files'].empty? &&
          cache['timestamp'] &&
          !cache_expired?(cache['timestamp'])
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

      def perform_scan
        epubs = []
        context = Models::ScannerContext.new(
          epubs: epubs,
          visited_paths: Set.new,
          depth: 0
        )

        scan_directories(context)

        warn "Found #{epubs.length} EPUB files" if DEBUG_MODE
        epubs
      end

      def scan_directories(context)
        all_dirs = build_directory_list

        warn "Scanning directories: #{all_dirs.join(', ')}" if DEBUG_MODE

        all_dirs.each do |start_dir|
          break if context.epubs.length >= MAX_FILES

          warn "Scanning: #{start_dir}" if DEBUG_MODE
          scan_directory(start_dir, context)
        end
      end

      def build_directory_list
        directories = priority_directories + other_directories
        directories.uniq.select { |dir| safe_directory_exists?(dir) }
      end

      def priority_directories
        [
          '~/Books',
          '~/Documents/Books',
          '~/Downloads',
          '~/Desktop',
          '~/Documents',
          '~/Library/Mobile Documents',
        ].map { |dir| File.expand_path(dir) }
      end

      def other_directories
        [
          '~',
          '~/Dropbox',
          '~/Google Drive',
          '~/OneDrive',
        ].map { |dir| File.expand_path(dir) }
      end

      def safe_directory_exists?(dir)
        Dir.exist?(dir)
      rescue StandardError
        false
      end

      def scan_directory(dir, context)
        return unless context.can_scan?(dir, MAX_DEPTH, MAX_FILES)

        context.mark_visited(dir)
        process_directory_entries(dir, context)
      rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
        # Skip directories we can't access
      rescue StandardError => e
        warn "Error scanning #{dir}: #{e.message}" if DEBUG_MODE
      end

      def process_directory_entries(dir, context)
        Dir.entries(dir).each do |entry|
          next if entry.start_with?('.')

          path = File.join(dir, entry)
          next if context.visited_paths.include?(path)

          process_entry(path, context)
        end
      end

      def process_entry(path, context)
        if File.directory?(path)
          process_directory(path, context)
        elsif epub_file?(path)
          add_epub(path, context.epubs)
        end
      rescue StandardError
        # Skip items we can't process
      end

      def process_directory(path, context)
        return if skip_directory?(path)

        scan_directory(path, context.with_deeper_depth)
      end

      def skip_directory?(path)
        base = File.basename(path).downcase
        Constants::SKIP_DIRS.map(&:downcase).include?(base)
      end

      def epub_file?(path)
        path.downcase.end_with?('.epub') &&
          File.readable?(path) &&
          File.size(path).positive?
      end

      def add_epub(path, epubs)
        epubs << {
          'path' => path,
          'name' => File.basename(path, '.epub').gsub(/[_-]/, ' '),
          'size' => File.size(path),
          'modified' => File.mtime(path).iso8601,
          'dir' => File.dirname(path),
        }
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
