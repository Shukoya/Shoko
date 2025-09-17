# frozen_string_literal: true

module EbookReader
  module Application
    # Handles pagination builds (dynamic/absolute) and progress overlay.
    # Keeps heavy orchestration out of ReaderController while preserving behavior.
    class PaginationOrchestrator
      def initialize(dependencies)
        @dependencies = dependencies
        @terminal_service = @dependencies.resolve(:terminal_service)
        @frame_coordinator = Application::FrameCoordinator.new(@dependencies)
      end

      # Performs the initial pagination calculation with a loading overlay.
      # Returns a hash with optional :page_map_cache for absolute mode.
      def initial_build(doc, state, page_calculator)
        return { page_map_cache: nil } unless doc

        height, width = @terminal_service.size
        begin_loading(state, 'Opening book…')

        cache = nil
        begin
          cache = if dynamic_mode?(state) && page_calculator
                    build_dynamic(doc, state, page_calculator, width, height)
                  else
                    build_absolute(doc, state, page_calculator, width, height)
                  end
        rescue StandardError
          cache = nil
        ensure
          end_loading(state)
        end
        { page_map_cache: cache }
      end

      # Rebuilds dynamic pagination with a loading overlay and precise restore.
      def rebuild_dynamic(doc, state, page_calculator)
        return :pass unless EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(state) == :dynamic

        height, width = @terminal_service.size

        # capture current logical line offset for precise restore
        prev_idx = state.get(%i[reader current_page_index]).to_i
        prev_page = page_calculator.get_page(prev_idx)
        line_offset = prev_page ? prev_page[:start_line] : 0
        chapter_index = state.get(%i[reader current_chapter]) || 0

        begin_loading(state, 'Rebuilding pagination…')

        # Store pending precise restore so the calculator can apply it
        state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                         pending_progress: {
                           chapter_index: chapter_index,
                           line_offset: line_offset,
                         }
                       ))

        page_calculator.build_dynamic_map!(width, height, doc, state) { |d, t| update_progress(state, d, t) }

        begin
          page_calculator.apply_pending_precise_restore!(state)
        rescue StandardError
          # best-effort
        end

        end_loading(state)
        :handled
      end

      private

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

      def build_dynamic(doc, state, page_calculator, width, height)
        page_calculator.build_dynamic_map!(width, height, doc, state) { |d, t| update_progress(state, d, t) }
        page_calculator.apply_pending_precise_restore!(state)
        nil
      end

      def build_absolute(doc, state, page_calculator, width, height)
        page_map = page_calculator.build_absolute_map!(width, height, doc, state) do |d, t|
          update_progress(state, d, t)
        end
        view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
        line_spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
        cache_key = "#{width}x#{height}-#{view_mode}-#{line_spacing}"
        { key: cache_key, map: page_map, total: page_map.sum }
      end
    end
  end
end
