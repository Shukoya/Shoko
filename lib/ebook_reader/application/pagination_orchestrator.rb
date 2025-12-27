# frozen_string_literal: true

require_relative '../infrastructure/kitty_graphics'

module EbookReader
  module Application
    # Handles pagination builds (dynamic/absolute) and progress overlay.
    # Keeps heavy orchestration out of ReaderController while preserving behavior.
    class PaginationOrchestrator
      # Aggregates pagination inputs and provides small helpers for map building.
      class Context
        attr_reader :doc, :state, :page_calculator, :dimensions

        def initialize(doc:, state:, page_calculator:, dimensions:)
          @doc = doc
          @state = state
          @page_calculator = page_calculator
          @dimensions = dimensions
        end

        def width
          dimensions[0]
        end

        def height
          dimensions[1]
        end

        def dynamic?
          false
        end

        def view_mode
          EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
        end

        def line_spacing
          EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
        end

        def kitty_images?
          EbookReader::Infrastructure::KittyGraphics.enabled_for?(state)
        end

        def pending_progress_payload
          current_chapter = state.get(%i[reader current_chapter]) || 0
          current_index = state.get(%i[reader current_page_index]).to_i
          page = page_calculator.get_page(current_index)
          {
            chapter_index: current_chapter,
            line_offset: page ? page[:start_line] : 0,
          }
        end

        def build_dynamic!(progress: nil)
          Infrastructure::PerfTracer.measure('pagination.build') do
            page_calculator.build_dynamic_map!(width, height, doc, state) do |done, total|
              progress&.call(done, total)
            end
          end
          page_calculator.apply_pending_precise_restore!(state)
        end

        def build_absolute!(progress: nil)
          Infrastructure::PerfTracer.measure('pagination.build') do
            page_calculator.build_absolute_map!(width, height, doc, state) do |done, total|
              progress&.call(done, total)
            end
          end
        end

        def clamp_dynamic_index!
          total = page_calculator.total_pages.to_i
          return if total <= 0

          current = state.get(%i[reader current_page_index]).to_i
          clamped = current.clamp(0, total - 1)
          state.dispatch(
            EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: clamped)
          )
        end
      end

      # Context for dynamic pagination builds.
      class DynamicContext < Context
        def dynamic?
          true
        end

        def build_full_map(progress: nil)
          build_dynamic!(progress: progress)
          nil
        end

        def refresh_after_resize
          build_dynamic!
          clamp_dynamic_index!
        end

        def rebuild_after_config_change
          payload = pending_progress_payload
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_progress: payload))
          build_dynamic!
          clamp_dynamic_index!
        end

        def build_initial_map(progress:)
          build_dynamic!(progress: progress)
          nil
        end
      end

      # Context for absolute pagination builds.
      class AbsoluteContext < Context
        def build_full_map(progress: nil)
          build_absolute!(progress: progress)
        end

        def refresh_after_resize
          build_absolute!
        end

        def rebuild_after_config_change
          build_absolute!
        end

        def build_initial_map(progress:)
          build_absolute!(progress: progress)
        end
      end

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
        context = build_context(doc, state, page_calculator, dimensions: terminal_dimensions)
        return { page_map_cache: nil } unless context

        cache = nil
        with_loading(state, 'Opening book…') do
          cache = build_initial_map(context)
        end
        { page_map_cache: cache }
      end

      # Build pagination immediately (no overlays) and return page-map data for absolute mode.
      def build_full_map!(doc, state, page_calculator, dimensions, &block)
        context = build_context(doc, state, page_calculator, dimensions: dimensions)
        return nil unless context

        context.build_full_map(progress: block)
      end

      # Non-bang variant to satisfy safe-method expectations.
      def build_full_map(doc, state, page_calculator, dimensions, &)
        build_full_map!(doc, state, page_calculator, dimensions, &)
      end

      # Refresh pagination after a terminal resize.
      def refresh_after_resize(doc, state, page_calculator, dimensions)
        context = build_context(doc, state, page_calculator, dimensions: dimensions)
        return unless context

        context.refresh_after_resize
      end

      # Rebuild pagination when layout-affecting config (view mode, line spacing, page numbering)
      # changes. Preserves the current reading position as precisely as possible.
      def rebuild_after_config_change(doc, state, page_calculator, dimensions)
        context = build_context(doc, state, page_calculator, dimensions: dimensions)
        return unless context

        context.rebuild_after_config_change
      rescue StandardError
        nil
      end

      # Rebuilds dynamic pagination with a loading overlay and precise restore.
      def rebuild_dynamic(doc, state, page_calculator)
        context = build_context(doc, state, page_calculator, dimensions: terminal_dimensions)
        return :pass unless context&.dynamic?

        payload = context.pending_progress_payload

        with_loading(state, 'Rebuilding pagination…') do
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_progress: payload))
          context.build_dynamic!(progress: progress_callback_for(state))
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

      def build_initial_map(context)
        progress = progress_callback_for(context.state)
        map = context.build_initial_map(progress: progress)
        map ? build_absolute_cache_entry(context, map) : nil
      rescue StandardError
        nil
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

      def build_absolute_cache_entry(context, page_map)
        key = @pagination_cache&.layout_key(
          context.width,
          context.height,
          context.view_mode,
          context.line_spacing,
          kitty_images: context.kitty_images?
        )
        {
          key: key,
          map: page_map,
          total: Array(page_map).sum,
        }
      end

      def terminal_dimensions
        height, width = @terminal_service.size
        [width, height]
      end

      def build_context(doc, state, page_calculator, dimensions:)
        return nil unless doc && page_calculator

        context_class =
          if EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(state) == :dynamic
            DynamicContext
          else
            AbsoluteContext
          end
        context_class.new(doc: doc, state: state, page_calculator: page_calculator, dimensions: dimensions)
      end

      def progress_callback_for(state)
        ->(done, total) { update_progress(state, done, total) }
      end
    end
  end
end
