# frozen_string_literal: true

require 'forwardable'
# Legacy reader modes removed (help/toc/bookmarks now rendered via components)
require_relative 'constants/ui_constants'
require_relative 'errors'
require_relative 'constants/messages'
require_relative 'application/annotation_editor_overlay_session'
require_relative 'application/reader_lifecycle'
require_relative 'application/reader_render_coordinator'
require_relative 'application/pagination_coordinator'
require_relative 'input/dispatcher'
require_relative 'application/frame_coordinator'
require_relative 'application/render_pipeline'
require_relative 'application/pending_jump_handler'

module EbookReader
  # Coordinator class for the reading experience.
  #
  # This refactored ReaderController now delegates responsibilities to focused controllers/services:
  # - Domain::Services::NavigationService: handles page/chapter navigation (via input bindings)
  # - UIController: handles mode switching and UI state
  # - StateController: handles persistence and state management
  # - InputController: handles all input processing
  #
  # The ReaderController now focuses only on:
  # - Component layout and rendering coordination
  # - Controller coordination and delegation
  # - Main application loop
  #
  # @attr_reader doc [EPUBDocument] The loaded EPUB document.
  # @attr_reader state [Infrastructure::ObserverStateStore] The current state of the reader.
  class ReaderController
    extend Forwardable
    include Constants::UIConstants
    # Helpers::ReaderHelpers removed; wrapping is provided by DI-backed WrappingService
    include Input::KeyDefinitions::Helpers

    # Core runtime context for the reader.
    Context = Struct.new(:path, :dependencies, :state, :doc, :metrics_start_time, :memo, keyword_init: true)
    # Service references used across the reader lifecycle.
    Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation, keyword_init: true)
    # Group UI/state/input controllers for delegation.
    ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller, keyword_init: true)
    # Group lifecycle/render/pagination coordinators for delegation.
    Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator, keyword_init: true)

    attr_reader :context, :services, :controllers, :coordinators

    def_delegators :context, :path, :dependencies, :state, :doc, :metrics_start_time
    def_delegators :services, :page_calculator, :terminal_service, :clipboard_service, :instrumentation
    def_delegators :controllers, :ui_controller, :state_controller, :input_controller
    def_delegators :coordinators, :lifecycle, :pagination_coordinator, :render_coordinator

    # Navigation is handled via Domain::NavigationService through input commands

    def_delegators :ui_controller, :switch_mode, :open_toc, :open_bookmarks, :open_annotations,
                   :show_help, :toggle_view_mode, :increase_line_spacing, :decrease_line_spacing,
                   :toggle_page_numbering_mode, :sidebar_down, :sidebar_up, :sidebar_select,
                   :handle_popup_action

    def_delegators :state_controller, :save_progress, :load_progress, :load_bookmarks,
                   :add_bookmark, :jump_to_bookmark, :delete_selected_bookmark, :quit_to_menu,
                   :quit_application

    def_delegators :input_controller, :handle_popup_navigation, :handle_popup_action_key,
                   :handle_popup_cancel, :handle_popup_menu_input

    def_delegators :render_coordinator, :draw_screen, :refresh_highlighting, :force_redraw,
                   :render_loading_overlay, :build_component_layout, :rebuild_root_layout,
                   :apply_theme_palette

    def_delegators :pagination_coordinator, :pending_initial_calculation?,
                   :perform_initial_calculations_if_needed, :defer_page_map?,
                   :schedule_background_page_map_build, :clear_defer_page_map!,
                   :rebuild_pagination, :invalidate_pagination_cache

    def_delegators :lifecycle, :run, :background_worker

    def initialize(epub_path, _config = nil, dependencies = nil)
      deps = dependencies || Domain::ContainerFactory.create_default_container
      state_store = deps.resolve(:global_state)
      @context = Context.new(path: epub_path,
                             dependencies: deps,
                             state: state_store,
                             doc: nil,
                             metrics_start_time: nil,
                             memo: {})
      @services = Services.new(
        page_calculator: deps.resolve(:page_calculator),
        terminal_service: deps.resolve(:terminal_service),
        clipboard_service: deps.resolve(:clipboard_service),
        instrumentation: resolve_optional(:instrumentation_service)
      )
      lifecycle = Application::ReaderLifecycle.new(self,
                                                  dependencies: deps,
                                                  terminal_service: terminal_service)
      @coordinators = Coordinators.new(lifecycle: lifecycle,
                                       pagination_coordinator: nil,
                                       render_coordinator: nil)
      lifecycle.ensure_background_worker

      # Load document before creating controllers that depend on it
      @context.doc = preload_document_from_dependencies
      reset_navigable_toc_cache! if doc
      load_document unless doc
      # Expose current book path in state for downstream services/screens
      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(book_path: path))

      # Initialize focused controllers with proper dependencies including document
      ui = EbookReader::Controllers::UIController.new(state, deps)
      sc = EbookReader::Controllers::StateController.new(state, doc, epub_path, deps)
      input = EbookReader::Controllers::InputController.new(state, deps)
      @controllers = ControllerRefs.new(ui_controller: ui,
                                        state_controller: sc,
                                        input_controller: input)

      # Register controllers in the dependency container for components that resolve them
      deps.register(:ui_controller, ui)
      deps.register(:state_controller, sc)
      deps.register(:input_controller, input)
      # Expose reader controller for components/controllers needing cleanup hooks
      deps.register(:reader_controller, self)

      frame_coordinator = Application::FrameCoordinator.new(deps)
      render_pipeline = Application::RenderPipeline.new(deps)
      pagination = Application::PaginationCoordinator.new(
        dependencies: Application::PaginationCoordinator::Dependencies.new(
          state: state,
          doc: doc,
          page_calculator: page_calculator,
          layout_service: deps.resolve(:layout_service),
          terminal_service: terminal_service,
          pagination_cache: resolve_optional(:pagination_cache),
          frame_coordinator: frame_coordinator,
          ui_controller: ui,
          render_callback: -> { force_redraw; draw_screen },
          background_worker_provider: -> { background_worker }
        )
      )
      render = Application::ReaderRenderCoordinator.new(
        dependencies: Application::ReaderRenderCoordinator::Dependencies.new(
          controller: self,
          state: state,
          dependencies: deps,
          terminal_service: terminal_service,
          frame_coordinator: frame_coordinator,
          render_pipeline: render_pipeline,
          ui_controller: ui,
          wrapping_service: wrapping_service,
          pagination: pagination,
          doc: doc
        )
      )
      @coordinators.pagination_coordinator = pagination
      @coordinators.render_coordinator = render

      apply_theme_palette

      # Do not load saved data synchronously to keep first paint fast.
      # Pending jump application will occur after progress load in run.
      apply_pending_jump_if_present

      # Build UI components
      build_component_layout
      input_controller.setup_input_dispatcher(self)

      # Observe sidebar visibility changes to rebuild layout
      state.add_observer(self, %i[reader sidebar_visible], %i[config theme],
                         %i[config view_mode], %i[config line_spacing],
                         %i[config page_numbering_mode],
                         %i[config kitty_images])
    end

    # Observer callback for state changes
    def state_changed(path, _old_value, _new_value)
      case path
      when %i[reader sidebar_visible]
        rebuild_root_layout
      when %i[config theme]
        apply_theme_palette
      when %i[config view_mode], %i[config line_spacing], %i[config page_numbering_mode], %i[config kitty_images]
        begin
          pagination_coordinator.rebuild_after_config_change
        rescue StandardError
          # best-effort rebuild; avoid crashing on layout changes
        end
        force_redraw
      end
    end

    def perform_first_paint
      instrumentation&.time('render.first_paint') { draw_screen }
      unless metrics_start_time
        instrumentation&.cancel_trace
        return
      end

      first_paint_completed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ttfp = first_paint_completed_at - metrics_start_time
      instrumentation&.record_metric('render.first_paint.ttfp', ttfp, 0)
      instrumentation&.record_trace('render.first_paint.ttfp', ttfp)
      open_type = if doc.respond_to?(:cached?) && doc.cached?
                    'warm'
                  else
                    'cold'
                  end
      instrumentation&.complete_trace(open_type:, total_duration: ttfp)
    end

    def dispatch_input_keys(keys)
      if annotations_overlay_active? && !annotation_editor_visible?
        input_controller.handle_annotations_overlay_input(keys)
      elsif popup_menu_visible?
        input_controller.handle_popup_menu_input(keys)
      else
        keys.each { |key| input_controller.handle_key(key) }
      end
    end

    def annotations_overlay_active?
      overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotations_overlay(state)
      overlay.respond_to?(:visible?) && overlay.visible?
    end

    def annotation_editor_visible?
      editor_overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
      editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
    end

    def popup_menu_visible?
      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(state)
      popup_menu&.visible
    end

    # Main application loop
    def main_loop
      ReaderEventLoop.new(self, state, metrics_start_time, instrumentation).run
    end

    def mark_metrics_start!
      context.metrics_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Page calculation and navigation support
    # Compatibility methods for legacy mode handlers
    def exit_help
      ui_controller.switch_mode(:read)
    end

    def exit_toc
      ui_controller.switch_mode(:read)
    end

    def exit_bookmarks
      ui_controller.switch_mode(:read)
    end

    def toc_down
      current = state.get(%i[reader toc_selected]) || 0
      next_index = next_navigable_toc_index(current)
      return if next_index == current

      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                        toc_selected: next_index,
                        sidebar_toc_selected: next_index
                      ))
    end

    def toc_up
      current = state.get(%i[reader toc_selected]) || 0
      next_index = previous_navigable_toc_index(current)
      return if next_index == current

      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                        toc_selected: next_index,
                        sidebar_toc_selected: next_index
                      ))
    end

    def toc_select
      document = doc
      return unless document

      entries = document.respond_to?(:toc_entries) ? Array(document.toc_entries) : []
      if entries.empty?
        entries = Array(document.chapters).each_with_index.map do |chapter, idx|
          Domain::Models::TOCEntry.new(
            title: chapter&.title || "Chapter #{idx + 1}",
            href: nil,
            level: 0,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      selected = (state.get(%i[reader toc_selected]) || 0).to_i
      selected = selected.clamp(0, [entries.length - 1, 0].max)
      chapter_index = entries[selected]&.chapter_index
      return unless chapter_index

      nav = dependencies.resolve(:navigation_service)
      nav.jump_to_chapter(chapter_index)
    end

    def bookmark_down
      bookmarks = state.get(%i[reader bookmarks]) || []
      return if bookmarks.empty?

      current = (state.get(%i[reader bookmark_selected]) || 0).to_i
      next_index = [current + 1, bookmarks.length - 1].min
      return if next_index == current

      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: next_index))
    end

    def bookmark_up
      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: [state.get(%i[reader bookmark_selected]) - 1,
                                                                                                   0].max))
    end

    def bookmark_select
      jump_to_bookmark
    end

    private

    def resolve_optional(service_name)
      return dependencies.resolve(service_name) if dependencies.registered?(service_name)

      nil
    rescue StandardError
      nil
    end

    def memo
      context.memo ||= {}
    end

    def selection_service
      return memo[:selection_service] if memo.key?(:selection_service)

      memo[:selection_service] = begin
        dependencies.resolve(:selection_service)
      rescue StandardError
        nil
      end
    end

    def wrapping_service
      return memo[:wrapping_service] if memo.key?(:wrapping_service)

      memo[:wrapping_service] = if dependencies.registered?(:wrapping_service)
                                  dependencies.resolve(:wrapping_service)
                                end
    rescue StandardError
      memo[:wrapping_service] = nil
    end

    def preload_document_from_dependencies
      return nil unless dependencies.respond_to?(:registered?) && dependencies.registered?(:document)

      dependencies.resolve(:document)
    rescue StandardError
      nil
    end

    def load_document
      return doc if doc

      factory = dependencies.resolve(:document_service_factory)
      document_service = factory.call(path)
      @context.doc = document_service.load_document
      reset_navigable_toc_cache!

      # Register document in dependency container for services to access
      dependencies.register(:document, doc)
      # Expose chapter count for navigation service logic
      begin
        state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                          total_chapters: doc&.chapter_count || 0
                        ))
      rescue StandardError
        # best-effort
      end
      doc
    end

    def load_data
      state_controller.load_progress
      state_controller.load_bookmarks
      state_controller.refresh_annotations
    end

    def apply_pending_jump_if_present
      jump_handler.apply
    end

    def jump_handler
      memo[:jump_handler] ||= Application::PendingJumpHandler.new(state, dependencies, ui_controller)
    end

    def normalize_selection_for_state(range)
      service = selection_service
      return nil unless service

      service.normalize_range(state, range)
    end

    def initialize_page_calculations
      # left for compatibility; now handled by PaginationCoordinator
    end

    def read_input_keys
      terminal_service.read_keys_blocking(limit: 10)
    end

    # Override helper to delegate to the DI-backed wrapping service
    def wrap_lines(lines, width)
      service = wrapping_service
      if service
        chapter_index = state&.get(%i[reader current_chapter]) || 0
        return service.wrap_lines(lines, chapter_index, width)
      end
      # Fallback (tests/dev only)
      lines
    end

    def navigable_toc_indices
      return memo[:navigable_toc_indices] if memo[:navigable_toc_indices]

      entries = if doc.respond_to?(:toc_entries)
                  Array(doc.toc_entries)
                else
                  []
                end
      indices = []
      entries.each_with_index do |entry, idx|
        indices << idx if entry&.chapter_index
      end

      if indices.empty?
        fallback_count = entries.empty? ? doc&.chapters&.length.to_i : entries.length
        memo[:navigable_toc_indices] = (0...fallback_count).to_a
      else
        memo[:navigable_toc_indices] = indices
      end
    end

    def next_navigable_toc_index(current)
      indices = navigable_toc_indices
      indices.find { |idx| idx > current } || indices.last || current
    end

    def previous_navigable_toc_index(current)
      indices = navigable_toc_indices
      indices.reverse.find { |idx| idx < current } || indices.first || current
    end

    def reset_navigable_toc_cache!
      memo[:navigable_toc_indices] = nil
    end

    # Hook for subclasses (MouseableReader) to clear any active selection/popup
    def clear_selection!
      # no-op in base controller
    end

    def activate_annotation_editor_overlay_session
      return memo[:overlay_session] if memo[:overlay_session]

      memo[:overlay_session] = EbookReader::Application::AnnotationEditorOverlaySession.new(
        state,
        dependencies,
        ui_controller
      )
    end

    def deactivate_annotation_editor_overlay_session
      memo[:overlay_session] = nil
    end

    def current_editor_component
      return memo[:overlay_session] if memo[:overlay_session]&.active?

      deactivate_annotation_editor_overlay_session
      ui_controller.current_mode
    end

    # Ensure both UI state and any local selection handlers are cleared
    def cleanup_popup_state
      ui_controller.cleanup_popup_state
      clear_selection!
    end

    # Test helper moved to WrappingService#fetch_window_and_prefetch

    public :activate_annotation_editor_overlay_session,
           :deactivate_annotation_editor_overlay_session,
           :current_editor_component

    # Encapsulates the main reader event loop to tame ReaderController complexity.
    class ReaderEventLoop
      def initialize(controller, state, metrics_start_time, instrumentation)
        @controller = controller
        @state = state
        @metrics_start_time = metrics_start_time
        @instrumentation = instrumentation
        @tti_recorded = false
      end

      def run
        controller.perform_first_paint
        startup_reference = metrics_start_time

        while running?
          keys = controller.read_input_keys
          record_tti(startup_reference, keys)
          next if keys.empty?

          controller.dispatch_input_keys(keys)
          controller.draw_screen
        end
      end

      private

      attr_reader :controller, :state, :metrics_start_time, :instrumentation

      def running?
        EbookReader::Domain::Selectors::ReaderSelectors.running?(state)
      end

      def record_tti(startup_reference, keys)
        return if @tti_recorded
        return unless startup_reference && keys.any?

        instrumentation&.record_metric(
          'render.tti',
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - startup_reference,
          0
        )
        @tti_recorded = true
      end
    end
  end
end
