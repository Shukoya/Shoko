# frozen_string_literal: true

require_relative 'logger'

module EbookReader
  module Infrastructure
    # Single-thread worker with monitored queue and graceful shutdown semantics.
    class BackgroundWorker
      def initialize(name: 'reader-worker')
        @name = name
        @queue = Queue.new
        @shutdown = false
        @mutex = Mutex.new
        @thread = spawn_thread
      end

      def submit(&block)
        raise ArgumentError, 'block required' unless block

        @mutex.synchronize do
          raise WorkerStoppedError, 'worker is shutting down' if @shutdown

          @queue << block
        end
        true
      end

      def shutdown(timeout: 2.0)
        thread = nil
        @mutex.synchronize do
          return if @shutdown

          @shutdown = true
          thread = @thread
          @queue << nil if thread&.alive?
        end
        thread&.join(timeout)
      ensure
        @thread = nil
      end

      class WorkerStoppedError < StandardError; end

      private

      def spawn_thread
        Thread.new do
          Thread.current.name = @name if Thread.current.respond_to?(:name=)
          loop do
            job = @queue.pop
            break if job.nil? && @shutdown

            next unless job

            begin
              job.call
            rescue StandardError => e
              Infrastructure::Logger.error('Background worker job failed',
                                           worker: @name,
                                           error: e.message)
            end
          end
        end
      end
    end
  end
end
