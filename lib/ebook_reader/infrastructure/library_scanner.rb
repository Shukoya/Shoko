# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Handles EPUB library scanning operations (filesystem/OS concerns)
    class LibraryScanner
      attr_accessor :scan_status, :scan_message, :epubs

      def initialize
        @epubs = []
        @filtered_epubs = []
        @scan_status = :idle
        @scan_message = ''
        @scan_thread = nil
        @scan_results_queue = Queue.new
      end

      def load_cached
        @epubs = EPUBFinder.scan_system(false) || []
        @filtered_epubs = @epubs
        @scan_status = @epubs.empty? ? :idle : :done
        @scan_message = "Loaded #{@epubs.length} books from cache" if @scan_status == :done
      rescue StandardError => e
        @scan_status = :error
        @scan_message = "Cache load failed: #{e.message}"
        @epubs = []
        @filtered_epubs = []
      end

      def start_scan(force: false)
        return if @scan_thread&.alive?

        initialize_scan
        @scan_thread = create_scan_thread(force)
      end

      private

      def initialize_scan
        @scan_status = :scanning
        @scan_message = 'Scanning for EPUB files...'
        @epubs = []
        @filtered_epubs = []
      end

      def create_scan_thread(force)
        Thread.new do
          perform_scan_operation(force)
        rescue StandardError => e
          handle_scan_error(e)
        end
      end

      def perform_scan_operation(force)
        epubs = EPUBFinder.scan_system(force_refresh: force) || []
        sorted_epubs = epubs.sort_by { |e| (e['name'] || '').downcase }

        @scan_results_queue.push(
          status: :done,
          epubs: sorted_epubs,
          message: "Found #{sorted_epubs.length} books"
        )
      end

      def handle_scan_error(error)
        @scan_results_queue.push(
          status: :error,
          epubs: [],
          message: "Scan failed: #{error.message[0..50]}"
        )
      end

      public

      def process_results
        return if @scan_results_queue.empty?

        result = @scan_results_queue.pop
        @scan_status = result[:status]
        @scan_message = result[:message]
        result[:epubs]
      end

      def cleanup
        @scan_thread&.kill
      rescue StandardError
        nil
      end
    end
  end
end

