# frozen_string_literal: true

require 'forwardable'
# Legacy reader modes removed (help/toc/bookmarks now rendered via components)
require_relative 'constants/ui_constants'
require_relative 'errors'
require_relative 'constants/messages'
# presenter removed (unused)
require_relative 'components/surface'
require_relative 'components/rect'
require_relative 'components/layouts/vertical'
require_relative 'components/layouts/horizontal'
require_relative 'components/header_component'
require_relative 'components/content_component'
require_relative 'components/footer_component'
require_relative 'components/tooltip_overlay_component'
require_relative 'components/screens/loading_overlay_component'
require_relative 'components/sidebar_panel_component'
require_relative 'application/annotation_editor_overlay_session'
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

    attr_reader :doc, :path, :state, :page_calculator, :dependencies,
                :terminal_service, :input_controller, :metrics_start_time,
                :background_worker, :instrumentation

    # Navigation is handled via Domain::NavigationService through input commands

    def_delegators :@ui_controller, :switch_mode, :open_toc, :open_bookmarks, :open_annotations,
                   :show_help, :toggle_view_mode, :increase_line_spacing, :decrease_line_spacing,
                   :toggle_page_numbering_mode, :sidebar_down, :sidebar_up, :sidebar_select,
                   :handle_popup_action

    def_delegators :@state_controller, :save_progress, :load_progress, :load_bookmarks,
                   :add_bookmark, :jump_to_bookmark, :delete_selected_bookmark, :quit_to_menu,
                   :quit_application

    def_delegators :@input_controller, :handle_popup_navigation, :handle_popup_action_key,
                   :handle_popup_cancel, :handle_popup_menu_input

    def initialize(epub_path, _config = nil, dependencies = nil)
      @path = epub_path
      @dependencies = dependencies || Domain::ContainerFactory.create_default_container
      @state = @dependencies.resolve(:global_state)
      apply_theme_palette

      # Initialize document and services first
      @page_calculator = @dependencies.resolve(:page_calculator)
      @layout_service = @dependencies.resolve(:layout_service)
      @clipboard_service = @dependencies.resolve(:clipboard_service)
      @terminal_service = @dependencies.resolve(:terminal_service)
      @wrapping_service = @dependencies.resolve(:wrapping_service) if @dependencies.registered?(:wrapping_service)
      @instrumentation = resolve_optional(:instrumentation_service)
      @background_worker = resolve_existing(:background_worker)
      unless @background_worker
        @background_worker = build_background_worker(name: 'reader-background')
        @dependencies.register(:background_worker, @background_worker) if @background_worker
      end

      # Load document before creating controllers that depend on it
      @doc = preload_document_from_dependencies
      reset_navigable_toc_cache! if @doc
      load_document unless @doc
      # Expose current book path in state for downstream services/screens
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(book_path: @path))

      # Terminal dimensions are updated centrally by FrameCoordinator during rendering

      # Initialize focused controllers with proper dependencies including document
      @ui_controller = Controllers::UIController.new(@state, @dependencies)
      @state_controller = Controllers::StateController.new(@state, @doc, epub_path,
                                                           @dependencies)
      @input_controller = Controllers::InputController.new(@state, @dependencies)

      # Register controllers in the dependency container for components that resolve them
      @dependencies.register(:ui_controller, @ui_controller)
      @dependencies.register(:state_controller, @state_controller)
      @dependencies.register(:input_controller, @input_controller)
      # Expose reader controller for components/controllers needing cleanup hooks
      @dependencies.register(:reader_controller, self)

      # Frame lifecycle + rendering pipeline
      @frame_coordinator = Application::FrameCoordinator.new(@dependencies)
      @render_pipeline   = Application::RenderPipeline.new(@dependencies)
      @pagination_orchestrator = Application::PaginationOrchestrator.new(@dependencies)

      # Do not load saved data synchronously to keep first paint fast.
      # Pending jump application will occur after progress load in run.
      apply_pending_jump_if_present
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @last_rendered_state = {}

      # Build UI components
      build_component_layout
      @input_controller.setup_input_dispatcher(self)

      # Build unified overlay component (used for highlights and popups)
      coord = @dependencies.resolve(:coordinate_service)
      @overlay = Components::TooltipOverlayComponent.new(self, coordinate_service: coord)

      # Defer heavy page calculations until after terminal setup
      @pending_initial_calculation = true
      # If document is cache-backed, skip initial heavy computations for instant open
      if @doc.respond_to?(:cached?) && @doc.cached?
        @pending_initial_calculation = false
        @defer_page_map = true
        @defer_page_map = false if @page_calculator && @page_calculator.total_pages.to_i.positive?
      else
        @defer_page_map = false
      end

      # Observe sidebar visibility changes to rebuild layout
      @state.add_observer(self, %i[reader sidebar_visible], %i[config theme],
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
        rebuild_pagination_for_layout_change
      end
    end

    def run
      @terminal_service.setup
      @metrics_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # Delegate reader startup orchestration
      EbookReader::Application::ReaderStartupOrchestrator.new(@dependencies).start(self)
      main_loop
    ensure
      @background_worker&.shutdown
      @background_worker = nil
      @dependencies.register(:background_worker, nil)
      @terminal_service.cleanup
    end

    # Component-based drawing
    def draw_screen
      height, width = @terminal_service.size

      tick_notifications

      # Update page maps on resize
      if size_changed?(width, height)
        unless @defer_page_map
          @pagination_orchestrator.refresh_after_resize(@doc, @state, @page_calculator, [width, height])
        end
        # Clear wrapped-lines cache for prior width via WrappingService (if available)
        begin
          prior_width = @state.get(%i[reader last_width])
          @wrapping_service&.clear_cache_for_width(prior_width) if prior_width&.positive?
        rescue StandardError
          # best-effort cache clear
        end
      end

      @frame_coordinator.with_frame do |surface, root_bounds, _w, _h|
        # Special-case full-screen modes that render their own UI
        mode = @state.get(%i[reader mode])
        mode_component = @ui_controller.current_mode
        if mode == :annotation_editor && mode_component
          @render_pipeline.render_mode_component(mode_component, surface, root_bounds)
        else
          @render_pipeline.render_layout(surface, root_bounds, @layout, @overlay)
        end
      end
    end

    # Partial refresh hook for subclasses.
    # By default, re-renders the current screen without ending the frame.
    # MouseableReader layers selection/annotation highlights on top and then ends the frame.
    def refresh_highlighting
      draw_screen
    end

    def force_redraw
      @content_component&.invalidate
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
      open_type = if @doc.respond_to?(:cached?) && @doc.cached?
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
      overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotations_overlay(@state)
      overlay.respond_to?(:visible?) && overlay.visible?
    end

    def annotation_editor_visible?
      editor_overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
      editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
    end

    def popup_menu_visible?
      popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
      popup_menu&.visible
    end

    # Main application loop
    def main_loop
      ReaderEventLoop.new(self, @state, @metrics_start_time, instrumentation).run
    end

    # Page calculation and navigation support
    # Compatibility methods for legacy mode handlers
    def exit_help
      @ui_controller.switch_mode(:read)
    end

    def exit_toc
      @ui_controller.switch_mode(:read)
    end

    def exit_bookmarks
      @ui_controller.switch_mode(:read)
    end

    def toc_down
      current = @state.get(%i[reader toc_selected]) || 0
      next_index = next_navigable_toc_index(current)
      return if next_index == current

      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                        toc_selected: next_index,
                        sidebar_toc_selected: next_index
                      ))
    end

    def toc_up
      current = @state.get(%i[reader toc_selected]) || 0
      next_index = previous_navigable_toc_index(current)
      return if next_index == current

      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                        toc_selected: next_index,
                        sidebar_toc_selected: next_index
                      ))
    end

    def toc_select
      doc = @doc
      return unless doc

      entries = doc.respond_to?(:toc_entries) ? Array(doc.toc_entries) : []
      if entries.empty?
        entries = Array(doc.chapters).each_with_index.map do |chapter, idx|
          Domain::Models::TOCEntry.new(
            title: chapter&.title || "Chapter #{idx + 1}",
            href: nil,
            level: 0,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      selected = (@state.get(%i[reader toc_selected]) || 0).to_i
      selected = selected.clamp(0, [entries.length - 1, 0].max)
      chapter_index = entries[selected]&.chapter_index
      return unless chapter_index

      nav = @dependencies.resolve(:navigation_service)
      nav.jump_to_chapter(chapter_index)
    end

    def bookmark_down
      bookmarks = @state.get(%i[reader bookmarks]) || []
      return if bookmarks.empty?

      current = (@state.get(%i[reader bookmark_selected]) || 0).to_i
      next_index = [current + 1, bookmarks.length - 1].min
      return if next_index == current

      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: next_index))
    end

    def bookmark_up
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: [@state.get(%i[reader bookmark_selected]) - 1,
                                                                                                   0].max))
    end

    def bookmark_select
      jump_to_bookmark
    end

    def create_view_model
      builder = EbookReader::Application::ReaderViewModelBuilder.new(@state, @doc)
      builder.build(calculate_page_info_for_view_model)
    end

    # Public controller APIs used by the startup orchestrator (no reflection)
    def pending_initial_calculation?
      !!@pending_initial_calculation
    end

    def perform_initial_calculations_if_needed
      perform_initial_calculations_with_progress if pending_initial_calculation? && !preloaded_page_data?
      @pending_initial_calculation = false
    end

    def defer_page_map?
      !!@defer_page_map
    end

    def schedule_background_page_map_build
      return unless defer_page_map?

      if background_worker
        background_worker.submit { build_page_map_in_background }
      else
        Thread.new { build_page_map_in_background }
      end
    rescue StandardError
      @defer_page_map = false
    end

    def clear_defer_page_map!
      @defer_page_map = false
    end

    private

    def resolve_optional(service_name)
      return @dependencies.resolve(service_name) if @dependencies.registered?(service_name)

      nil
    rescue StandardError
      nil
    end

    def resolve_existing(service_name)
      resolve_optional(service_name)
    end

    def build_background_worker(name:)
      factory = resolve_optional(:background_worker_factory)
      return nil unless factory.respond_to?(:call)

      factory.call(name:)
    rescue StandardError
      nil
    end

    def preload_document_from_dependencies
      return nil unless @dependencies.respond_to?(:registered?) && @dependencies.registered?(:document)

      @dependencies.resolve(:document)
    rescue StandardError
      nil
    end

    def tick_notifications
      resolve_notification_service&.tick(@state)
    end

    def resolve_notification_service
      return @resolve_notification_service if defined?(@resolve_notification_service)

      @resolve_notification_service = begin
        @dependencies.resolve(:notification_service)
      rescue StandardError
        nil
      end
    end

    def selection_service
      @selection_service ||= begin
        @dependencies.resolve(:selection_service)
      rescue StandardError
        nil
      end
    end

    # Expose controlled flag setters for the orchestrator
    attr_writer :defer_page_map

    def load_document
      return @doc if @doc

      factory = @dependencies.resolve(:document_service_factory)
      document_service = factory.call(@path)
      @doc = document_service.load_document
      reset_navigable_toc_cache!

      # Register document in dependency container for services to access
      @dependencies.register(:document, @doc)
      # Expose chapter count for navigation service logic
      begin
        @state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                          total_chapters: @doc&.chapter_count || 0
                        ))
      rescue StandardError
        # best-effort
      end
      @doc
    end

    def load_data
      @state_controller.load_progress
      @state_controller.load_bookmarks
      @state_controller.refresh_annotations
    end

    def apply_pending_jump_if_present
      jump_handler.apply
    end

    def jump_handler
      @jump_handler ||= Application::PendingJumpHandler.new(@state, @dependencies, @ui_controller)
    end

    def build_component_layout
      vm_proc = method(:create_view_model)
      @header_component = Components::HeaderComponent.new(vm_proc)
      @content_component = Components::ContentComponent.new(self)
      @footer_component = Components::FooterComponent.new(vm_proc)
      @sidebar_component = Components::SidebarPanelComponent.new(@state, @dependencies)

      # Create main content area (may be wrapped in horizontal layout)
      @main_content_layout = Components::Layouts::Vertical.new([
                                                                 @header_component,
                                                                 @content_component,
                                                                 @footer_component,
                                                               ])

      # Root layout will be determined dynamically in draw_screen
      rebuild_root_layout
    end

    def rebuild_root_layout
      @layout = if @state.get(%i[reader sidebar_visible])
                  # Use horizontal layout with sidebar + main content
                  Components::Layouts::Horizontal.new(@sidebar_component, @main_content_layout)
                else
                  # Use just the main content layout
                  @main_content_layout
                end
    end

    def calculate_page_info_for_view_model
      calculator = Application::PageInfoCalculator.new(
        state: @state,
        doc: @doc,
        page_calculator: @page_calculator,
        layout_service: @layout_service,
        terminal_service: @terminal_service,
        pagination_orchestrator: @pagination_orchestrator,
        defer_page_map: @defer_page_map
      )
      calculator.calculate
    rescue StandardError
      { type: :single, current: 0, total: 0 }
    end

    def normalize_selection_for_state(range)
      service = selection_service
      return nil unless service

      service.normalize_range(@state, range)
    end

    def initialize_page_calculations
      # left for compatibility; now handled in perform_initial_calculations_with_progress
    end

    def size_changed?(width, height)
      @state.terminal_size_changed?(width, height)
    end

    def rebuild_pagination_for_layout_change
      return unless @doc && @page_calculator && @pagination_orchestrator

      height, width = @terminal_service.size
      @pagination_orchestrator.rebuild_after_config_change(@doc, @state, @page_calculator, [width, height])
      force_redraw
    rescue StandardError
      # best-effort rebuild; avoid crashing on layout changes
    end

    def build_page_map_in_background
      height, width = @terminal_service.size
      @pagination_orchestrator.build_full_map!(@doc, @state, @page_calculator, [width, height])
      @defer_page_map = false
      force_redraw
      # Ensure the screen reflects the updated state without waiting for a keypress
      begin
        draw_screen
      rescue StandardError
        # best-effort
      end
    rescue StandardError
      @defer_page_map = false
    end

    def read_input_keys
      @terminal_service.read_keys_blocking(limit: 10)
    end

    # Perform initial heavy page calculations with a visual progress overlay
    def perform_initial_calculations_with_progress
      return unless @doc

      result = @pagination_orchestrator.initial_build(@doc, @state, @page_calculator)
      pmc = result && result[:page_map_cache]
      @page_map_cache = pmc if pmc
      draw_screen
    end

    def render_loading_overlay
      @frame_coordinator.render_loading_overlay
    end

    # Rebuild pagination for current layout and restore position
    def rebuild_pagination(_key = nil)
      result = @pagination_orchestrator.rebuild_dynamic(@doc, @state, @page_calculator)
      draw_screen
      result
    end

    # Invalidate cached pagination for current layout and notify user
    def invalidate_pagination_cache(_key = nil)
      height, width = @terminal_service.size
      result = @pagination_orchestrator.invalidate_cache(@doc, @state, width: width, height: height)
      case result
      when :deleted
        @ui_controller.set_message('Pagination cache cleared')
      when :missing
        @ui_controller.set_message('No pagination cache for this layout')
      else
        @ui_controller.set_message('Failed to clear pagination cache')
      end
      :handled
    end

    def preloaded_page_data?
      if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic
        return @page_calculator&.total_pages&.positive?
      end

      @state.get(%i[reader total_pages]).to_i.positive?
    end

    # Override helper to delegate to the DI-backed wrapping service
    def wrap_lines(lines, width)
      if @wrapping_service
        chapter_index = @state&.get(%i[reader current_chapter]) || 0
        return @wrapping_service.wrap_lines(lines, chapter_index, width)
      end
      # Fallback (tests/dev only)
      lines
    end

    def navigable_toc_indices
      return @navigable_toc_indices if @navigable_toc_indices

      entries = if @doc.respond_to?(:toc_entries)
                  Array(@doc.toc_entries)
                else
                  []
                end
      indices = []
      entries.each_with_index do |entry, idx|
        indices << idx if entry&.chapter_index
      end

      if indices.empty?
        fallback_count = entries.empty? ? @doc&.chapters&.length.to_i : entries.length
        @navigable_toc_indices = (0...fallback_count).to_a
      else
        @navigable_toc_indices = indices
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
      @navigable_toc_indices = nil
    end

    # Hook for subclasses (MouseableReader) to clear any active selection/popup
    def clear_selection!
      # no-op in base controller
    end

    def activate_annotation_editor_overlay_session
      return @overlay_session if @overlay_session

      @overlay_session = EbookReader::Application::AnnotationEditorOverlaySession.new(
        @state,
        @dependencies,
        @ui_controller
      )
    end

    def deactivate_annotation_editor_overlay_session
      @overlay_session = nil
    end

    def current_editor_component
      return @overlay_session if @overlay_session&.active?

      deactivate_annotation_editor_overlay_session
      @ui_controller.current_mode
    end

    # Ensure both UI state and any local selection handlers are cleared
    def cleanup_popup_state
      @ui_controller.cleanup_popup_state
      clear_selection!
    end

    def apply_theme_palette
      theme = EbookReader::Domain::Selectors::ConfigSelectors.theme(@state) || :default
      palette = EbookReader::Constants::Themes.palette_for(theme)
      EbookReader::Components::RenderStyle.configure(palette)
    rescue StandardError
      EbookReader::Components::RenderStyle.configure(EbookReader::Constants::Themes::DEFAULT_PALETTE)
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
