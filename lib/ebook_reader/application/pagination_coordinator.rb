# frozen_string_literal: true

require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'

module EbookReader
  module Application
    # Coordinates pagination-related workflows for the reader.
    class PaginationCoordinator
      # Aggregated pagination dependencies.
      Dependencies = Struct.new(
        :state,
        :doc,
        :page_calculator,
        :layout_service,
        :terminal_service,
        :pagination_cache,
        :frame_coordinator,
        :ui_controller,
        :render_callback,
        :background_worker_provider,
        keyword_init: true
      )

      # State flags for deferred pagination behavior.
      Flags = Struct.new(:pending_initial_calculation, :defer_page_map, keyword_init: true)

      def initialize(dependencies:)
        @deps = dependencies
        @orchestrator = Application::PaginationOrchestrator.new(
          terminal_service: dependencies.terminal_service,
          pagination_cache: dependencies.pagination_cache,
          frame_coordinator: dependencies.frame_coordinator
        )
        @flags = Flags.new(pending_initial_calculation: true, defer_page_map: false)
        seed_flags
      end

      def pending_initial_calculation?
        @flags.pending_initial_calculation
      end

      def defer_page_map?
        @flags.defer_page_map
      end

      def clear_defer_page_map!
        @flags.defer_page_map = false
      end

      def perform_initial_calculations_if_needed
        perform_initial_calculations_with_progress if pending_initial_calculation? && !preloaded_page_data?
        @flags.pending_initial_calculation = false
      end

      def schedule_background_page_map_build
        return unless defer_page_map?

        submit_background_job { build_page_map_in_background }
      rescue StandardError
        @flags.defer_page_map = false
      end

      def refresh_after_resize(width:, height:)
        return if defer_page_map?

        session(dimensions: [width, height])&.refresh_after_resize
      end

      def rebuild_after_config_change
        session(dimensions: terminal_dimensions)&.rebuild_after_config_change
      rescue StandardError
        nil
      end

      def rebuild_dynamic
        result = session&.rebuild_dynamic
        render_callback&.call
        result
      end

      def rebuild_pagination(_key = nil)
        rebuild_dynamic
      end

      def invalidate_cache
        result = session(dimensions: terminal_dimensions)&.invalidate_cache || :missing
        apply_invalidate_message(result)
        :handled
      end

      def invalidate_pagination_cache(_key = nil)
        invalidate_cache
      end

      def page_info
        calculator = Application::PageInfoCalculator.new(
          dependencies: Application::PageInfoCalculator::Dependencies.new(
            state: deps.state,
            doc: deps.doc,
            page_calculator: deps.page_calculator,
            layout_service: deps.layout_service,
            terminal_service: deps.terminal_service,
            pagination_orchestrator: @orchestrator
          ),
          defer_page_map: defer_page_map?
        )
        calculator.calculate
      rescue StandardError
        { type: :single, current: 0, total: 0 }
      end

      private

      attr_reader :deps

      def render_callback
        deps.render_callback
      end

      def background_worker
        provider = deps.background_worker_provider
        provider&.call
      end

      def terminal_dimensions
        height, width = deps.terminal_service.size
        [width, height]
      end

      def session(dimensions: nil)
        @orchestrator.session(
          doc: deps.doc,
          state: deps.state,
          page_calculator: deps.page_calculator,
          dimensions: dimensions
        )
      end

      def perform_initial_calculations_with_progress
        return unless deps.doc

        session = session(dimensions: terminal_dimensions)
        return unless session

        session.initial_build
        render_callback&.call
      end

      def build_page_map_in_background
        session(dimensions: terminal_dimensions)&.build_full_map
        @flags.defer_page_map = false
        render_callback&.call
      rescue StandardError
        @flags.defer_page_map = false
      end

      def submit_background_job(&)
        worker = background_worker
        if worker
          worker.submit(&)
        else
          Thread.new do
            yield
          rescue StandardError
            # ignore background failures
          end
        end
      end

      def preloaded_page_data?
        if Domain::Selectors::ConfigSelectors.page_numbering_mode(deps.state) == :dynamic
          return deps.page_calculator&.total_pages&.positive?
        end

        deps.state.get(%i[reader total_pages]).to_i.positive?
      end

      def seed_flags
        return unless deps.doc.respond_to?(:cached?) && deps.doc.cached?

        @flags.pending_initial_calculation = false
        @flags.defer_page_map = true
        return unless deps.page_calculator && deps.page_calculator.total_pages.to_i.positive?

        @flags.defer_page_map = false
      end

      def apply_invalidate_message(result)
        return unless deps.ui_controller

        case result
        when :deleted
          deps.ui_controller.set_message('Pagination cache cleared')
        when :missing
          deps.ui_controller.set_message('No pagination cache for this layout')
        else
          deps.ui_controller.set_message('Failed to clear pagination cache')
        end
      end
    end
  end
end
