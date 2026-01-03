# frozen_string_literal: true

module EbookReader
  module Application
    # Manages reader startup and shutdown concerns (terminal setup, background worker).
    class ReaderLifecycle
      def initialize(controller, dependencies:, terminal_service:)
        @controller = controller
        @dependencies = dependencies
        @terminal_service = terminal_service
        @background_worker = nil
      end

      def ensure_background_worker(name: 'reader-background')
        @background_worker ||= resolve_existing(:background_worker)
        return @background_worker if @background_worker

        factory = resolve_optional(:background_worker_factory)
        return nil unless factory.respond_to?(:call)

        @background_worker = factory.call(name: name)
        @dependencies.register(:background_worker, @background_worker) if @background_worker
        @background_worker
      rescue StandardError
        nil
      end

      attr_reader :background_worker

      def run
        ensure_background_worker
        @terminal_service.setup
        @controller.mark_metrics_start!
        EbookReader::Application::ReaderStartupOrchestrator.new(@dependencies).start(@controller)
        @controller.main_loop
      ensure
        shutdown_background_worker
        @terminal_service.cleanup
      end

      def shutdown_background_worker
        @background_worker&.shutdown
      ensure
        @background_worker = nil
        @dependencies.register(:background_worker, nil)
      end

      private

      def resolve_existing(name)
        return nil unless @dependencies.respond_to?(:registered?) && @dependencies.registered?(name)

        @dependencies.resolve(name)
      rescue StandardError
        nil
      end

      def resolve_optional(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end
    end
  end
end
