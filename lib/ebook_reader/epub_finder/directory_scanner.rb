# frozen_string_literal: true

module EbookReader
  class EPUBFinder
    # Scans directories to locate EPUB files
    class DirectoryScanner
      def initialize(context)
        @context = context
      end

      def scan_all_directories
        all_dirs = build_directory_list
        warn "Scanning directories: #{all_dirs.join(', ')}" if EPUBFinder::DEBUG_MODE

        all_dirs.each do |dir|
          break if @context.epubs.length >= EPUBFinder::MAX_FILES

          warn "Scanning: #{dir}" if EPUBFinder::DEBUG_MODE
          scan_directory(dir)
        end
      end

      private

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

      def scan_directory(dir)
        return unless @context.can_scan?(dir, EPUBFinder::MAX_DEPTH, EPUBFinder::MAX_FILES)

        @context.mark_visited(dir)
        process_entries(dir)
      rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
        # Skip directories we can't access
      rescue StandardError => e
        warn "Error scanning #{dir}: #{e.message}" if EPUBFinder::DEBUG_MODE
      end

      def process_entries(dir)
        Dir.entries(dir).each do |entry|
          next if entry.start_with?('.')

          path = File.join(dir, entry)
          next if @context.visited_paths.include?(path)

          process_path(path)
        end
      end

      def process_path(path)
        if File.directory?(path)
          process_directory(path)
        elsif epub_file?(path)
          add_epub(path)
        end
      rescue StandardError
        # Skip items we can't process
      end

      def process_directory(path)
        return if skip_directory?(path)

        DirectoryScanner.new(@context.with_deeper_depth).scan_directory(path)
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

      def add_epub(path)
        @context.epubs << {
          'path' => path,
          'name' => File.basename(path, '.epub').gsub(/[_-]/, ' '),
          'size' => File.size(path),
          'modified' => File.mtime(path).iso8601,
          'dir' => File.dirname(path),
        }
      end
    end
  end
end
