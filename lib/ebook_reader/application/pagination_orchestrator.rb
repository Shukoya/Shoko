# frozen_string_literal: true

require_relative '../infrastructure/kitty_graphics'

module EbookReader
  module Application
    # Handles pagination builds (dynamic/absolute) and progress overlay.
    # Keeps heavy orchestration out of ReaderController while preserving behavior.
    class PaginationOrchestrator
      def initialize(dependencies)
        @dependencies = dependencies
        @terminal_service = @dependencies.resolve(:terminal_service)
        @frame_coordinator = Application::FrameCoordinator.new(@dependencies)
        @pagination_cache = begin
          @dependencies.resolve(:pagination_cache)
        rescue StandardError
          nil
        end
      end

      # Performs the initial pagination calculation with a loading overlay.
      # Returns a hash with optional :page_map_cache for absolute mode.
      def initial_build(doc, state, page_calculator)
        return { page_map_cache: nil } unless doc && page_calculator

        width, height = terminal_dimensions
        cache = nil
        with_loading(state, 'Opening book…') do
          cache = build_initial_map(doc, state, page_calculator, [width, height])
        end
        { page_map_cache: cache }
      end

      # Build pagination immediately (no overlays) and return page-map data for absolute mode.
      def build_full_map!(doc, state, page_calculator, dimensions, &)
        return nil unless doc && page_calculator

        return perform_absolute_build(doc, state, page_calculator, dimensions, &) unless dynamic_mode?(state)

        perform_dynamic_build(doc, state, page_calculator, dimensions, &)
        nil
      end

      # Refresh pagination after a terminal resize.
      def refresh_after_resize(doc, state, page_calculator, dimensions)
        return unless doc && page_calculator

        if dynamic_mode?(state)
          perform_dynamic_build(doc, state, page_calculator, dimensions)
          clamp_dynamic_index(state, page_calculator)
        else
          perform_absolute_build(doc, state, page_calculator, dimensions)
        end
      end

      # Rebuild pagination when layout-affecting config (view mode, line spacing, page numbering)
      # changes. Preserves the current reading position as precisely as possible.
      def rebuild_after_config_change(doc, state, page_calculator, dimensions)
        return unless doc && page_calculator

        width, height = dimensions
        if dynamic_mode?(state)
          payload = pending_progress_payload(state, page_calculator)
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_progress: payload))
          perform_dynamic_build(doc, state, page_calculator, [width, height])
          clamp_dynamic_index(state, page_calculator)
        else
          perform_absolute_build(doc, state, page_calculator, [width, height])
        end
      rescue StandardError
        nil
      end

      # Rebuilds dynamic pagination with a loading overlay and precise restore.
      def rebuild_dynamic(doc, state, page_calculator)
        return :pass unless dynamic_mode?(state) && page_calculator

        width, height = terminal_dimensions
        payload = pending_progress_payload(state, page_calculator)

        with_loading(state, 'Rebuilding pagination…') do
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_progress: payload))
          perform_dynamic_build(doc, state, page_calculator, [width, height]) do |done, total|
            update_progress(state, done, total)
          end
        end
        :handled
      end

      # Remove the cached pagination entry for the supplied dimensions.
      #
      # @return [Symbol] :deleted when cache entry removed, :missing when no entry existed,
      #   :error when removal fails.
      def invalidate_cache(doc, state, width:, height:)
        return :missing unless doc && @pagination_cache

        view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
        line_spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
        kitty_images = EbookReader::Infrastructure::KittyGraphics.enabled_for?(state)
        key = @pagination_cache.layout_key(width, height, view_mode,
                                           line_spacing, kitty_images: kitty_images)
        return :missing unless key && @pagination_cache.exists_for_document?(doc, key)

        @pagination_cache.delete_for_document(doc, key)
        :deleted
      rescue StandardError
        :error
      end

      private

      def build_initial_map(doc, state, page_calculator, dimensions)
        if dynamic_mode?(state)
          perform_dynamic_build(doc, state, page_calculator, dimensions) do |done, total|
            update_progress(state, done, total)
          end
          nil
        else
          map = perform_absolute_build(doc, state, page_calculator, dimensions) do |done, total|
            update_progress(state, done, total)
          end
          width, height = dimensions
          build_absolute_cache_entry(map, state, width, height)
        end
      rescue StandardError
        nil
      end

      def perform_dynamic_build(doc, state, page_calculator, dimensions, &block)
        width, height = dimensions
        Infrastructure::PerfTracer.measure('pagination.build') do
          page_calculator.build_dynamic_map!(width, height, doc, state) do |done, total|
            block&.call(done, total)
          end
        end
        page_calculator.apply_pending_precise_restore!(state)
      end

      def perform_absolute_build(doc, state, page_calculator, dimensions, &block)
        width, height = dimensions
        Infrastructure::PerfTracer.measure('pagination.build') do
          page_calculator.build_absolute_map!(width, height, doc, state) do |done, total|
            block&.call(done, total)
          end
        end
      end

      def dynamic_mode?(state)
        EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(state) == :dynamic
      end

      def begin_loading(state, message)
        state.dispatch(EbookReader::Domain::Actions::UpdateUILoadingAction.new(
                         loading_active: true,
                         loading_message: message,
                         loading_progress: 0.0
                       ))
        @frame_coordinator.render_loading_overlay
      end

      def end_loading(state)
        state.dispatch(EbookReader::Domain::Actions::UpdateUILoadingAction.new(
                         loading_active: false,
                         loading_message: nil
                       ))
      end

      def update_progress(state, done, total)
        progress = EbookReader::Application::ProgressHelper.ratio(done, total)
        state.dispatch(EbookReader::Domain::Actions::UpdateUILoadingAction.new(
                         loading_progress: progress
                       ))
        @frame_coordinator.render_loading_overlay
      end

      def with_loading(state, message)
        begin_loading(state, message)
        yield
      ensure
        end_loading(state)
      end

      def build_absolute_cache_entry(page_map, state, width, height)
        view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
        line_spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
        kitty_images = EbookReader::Infrastructure::KittyGraphics.enabled_for?(state)
        key = if @pagination_cache
                @pagination_cache.layout_key(width, height, view_mode, line_spacing, kitty_images: kitty_images)
              else
                nil
              end
        {
          key: key,
          map: page_map,
          total: Array(page_map).sum,
        }
      end

      def pending_progress_payload(state, page_calculator)
        current_chapter = state.get(%i[reader current_chapter]) || 0
        current_index = state.get(%i[reader current_page_index]).to_i
        page = page_calculator.get_page(current_index)
        {
          chapter_index: current_chapter,
          line_offset: page ? page[:start_line] : 0,
        }
      end

      def terminal_dimensions
        height, width = @terminal_service.size
        [width, height]
      end

      def clamp_dynamic_index(state, page_calculator)
        total = page_calculator.total_pages.to_i
        return if total <= 0

        current = state.get(%i[reader current_page_index]).to_i
        clamped = current.clamp(0, total - 1)
        state.dispatch(
          EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: clamped)
        )
      end
    end
  end
end
