# frozen_string_literal: true

module EbookReader
  module Application
    # Orchestrates reader startup steps: terminal prep, progress restore,
    # pagination preload, and background data loads.
    class ReaderStartupOrchestrator
      def initialize(dependencies)
        @dependencies = dependencies
        @terminal_service = @dependencies.resolve(:terminal_service)
      end

      # Execute startup sequence using the controller as context
      # @param controller [EbookReader::ReaderController]
      def start(controller)
        state = controller.state
        page_calculator = controller.page_calculator
        doc = controller.doc
        sc = nil

        # Query terminal size (FrameCoordinator will update state during rendering)
        height, width = begin
          @terminal_service.size
        rescue StandardError
          [nil, nil]
        end

        # Load progress after terminal is ready
        sc = safe_resolve_state_controller
        sc&.load_progress

        # For cached books in dynamic mode, try to load pagination cache synchronously
        begin
          if doc.respond_to?(:cached?) && doc.cached? &&
             EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(state) == :dynamic
            view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
            line_spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
            key = EbookReader::Infrastructure::PaginationCache.layout_key(width, height, view_mode,
                                                                          line_spacing)
            if EbookReader::Infrastructure::PaginationCache.exists_for_document?(doc, key)
              page_calculator.build_dynamic_map!(width, height, doc, state)
              page_calculator.apply_pending_precise_restore!(state)
              controller.clear_defer_page_map!
            end
          end
        rescue StandardError
          # ignore; fall back to deferred build
        end

        # Perform initial calculations if needed
        controller.perform_initial_calculations_if_needed if controller.pending_initial_calculation?

        # Schedule background page-map build for instant-open path
        controller.schedule_background_page_map_build if controller.defer_page_map?

        # Background load bookmarks and annotations
        Thread.new(sc) do |svc_initial|
          begin
            svc = svc_initial || safe_resolve_state_controller
            if svc
              svc.load_bookmarks
              svc.refresh_annotations
            end
          rescue StandardError
            # ignore background failures
          end
        end
      end

      private

      def safe_resolve_state_controller
        @dependencies.resolve(:state_controller)
      rescue StandardError
        nil
      end
    end
  end
end
