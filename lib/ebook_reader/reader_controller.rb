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
require_relative 'input/dispatcher'
require_relative 'application/frame_coordinator'
require_relative 'application/render_pipeline'
require_relative 'infrastructure/performance_monitor'
require_relative 'infrastructure/background_worker'

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

    attr_reader :doc, :path, :state, :page_calculator, :dependencies, :terminal_service

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
      @background_worker = Infrastructure::BackgroundWorker.new(name: 'reader-background')
      @dependencies.register(:background_worker, @background_worker)

      # Load document before creating controllers that depend on it
      load_document
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
      else
        @defer_page_map = false
      end

      # Observe sidebar visibility changes to rebuild layout
      @state.add_observer(self, %i[reader sidebar_visible], %i[config theme])
    end

    # Observer callback for state changes
    def state_changed(path, _old_value, _new_value)
      case path
      when %i[reader sidebar_visible]
        rebuild_root_layout
      when %i[config theme]
        apply_theme_palette
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

      # Update page maps on resize
      if size_changed?(width, height)
        refresh_page_map(width, height) unless @defer_page_map
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

    # Main application loop
    def main_loop
      Infrastructure::PerformanceMonitor.time('render.first_paint') { draw_screen }
      if @metrics_start_time
        first_paint_completed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Infrastructure::PerformanceMonitor.record_metric(
          'render.first_paint.ttfp',
          first_paint_completed_at - @metrics_start_time,
          0
        )
      end
      tti_recorded = false
      startup_reference = @metrics_start_time
      while EbookReader::Domain::Selectors::ReaderSelectors.running?(@state)
        keys = read_input_keys
        if !tti_recorded && startup_reference && keys.any?
          Infrastructure::PerformanceMonitor.record_metric(
            'render.tti',
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - startup_reference,
            0
          )
          tti_recorded = true
        end
        next if keys.empty?

        # Intercept keys for popup menu if visible
        popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
        if popup_menu&.visible
          @input_controller.handle_popup_menu_input(keys)
        else
          keys.each { |k| @input_controller.handle_key(k) }
        end
        draw_screen
      end
    end

    # Page calculation and navigation support
    def calculate_current_pages
      return { current: 0, total: 0 } unless @state.get(%i[config show_page_numbers])

      numbering_mode = @state.get(%i[config page_numbering_mode])
      if numbering_mode == :dynamic
        return { current: 0, total: 0 } unless @page_calculator

        current = (@state.get(%i[reader current_page_index]) || 0) + 1
        total = @page_calculator.total_pages.to_i
        # If dynamic map not ready yet, return current with unknown total
        total = 0 if total <= 0
        { current: current, total: total }
      else
        height, width = @terminal_service.size
        view_mode = @state.get(%i[config view_mode])
        _, content_height = @layout_service.calculate_metrics(width, height, view_mode)
        actual_height = adjust_for_line_spacing(content_height)

        return { current: 0, total: 0 } if actual_height <= 0

        # Avoid heavy page-map build on first frame when deferred
        page_map = Array(@state.get(%i[reader page_map]) || [])
        if !@defer_page_map && (size_changed?(width, height) || page_map.empty?)
          update_page_map(width, height)
          page_map = Array(@state.get(%i[reader page_map]) || [])
        end

        current_chapter = (@state.get(%i[reader current_chapter]) || 0)
        pages_before = page_map[0...current_chapter].sum
        line_offset = if view_mode == :split
                        @state.get(%i[reader left_page])
                      else
                        @state.get(%i[reader single_page])
                      end
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter
        total_pages = @state.get(%i[reader total_pages]).to_i
        # When deferred, total may be 0; footer will show current without total
        { current: current_global_page, total: total_pages }
      end
    end

    def calculate_split_pages
      unless @state.get(%i[config show_page_numbers])
        return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
      end

      numbering_mode = @state.get(%i[config page_numbering_mode])
      if numbering_mode == :dynamic
        return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } } unless @page_calculator

        left_page = @state.get(%i[reader current_page_index]) + 1
        total_pages = @page_calculator.total_pages
        right_page = [left_page + 1, total_pages].min

        { left: { current: left_page, total: total_pages }, right: { current: right_page, total: total_pages } }
      else
        height, width = @terminal_service.size
        _, content_height = @layout_service.calculate_metrics(width, height, :split)
        actual_height = adjust_for_line_spacing(content_height)

        return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } } if actual_height <= 0

        pm = Array(@state.get(%i[reader page_map]) || [])
        if size_changed?(width, height) || pm.empty?
          update_page_map(width, height)
          pm = Array(@state.get(%i[reader page_map]) || [])
        end
        total_pages = @state.get(%i[reader total_pages])
        unless total_pages.positive?
          return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
        end

        current_chapter = (@state.get(%i[reader current_chapter]) || 0)
        pages_before = pm[0...current_chapter].sum

        # Calculate left page
        left_line_offset = @state.get(%i[reader left_page]) || 0
        left_page_in_chapter = (left_line_offset.to_f / actual_height).floor + 1
        left_current = pages_before + left_page_in_chapter

        # Calculate right page
        right_line_offset = @state.get(%i[reader right_page]) || actual_height
        right_page_in_chapter = (right_line_offset.to_f / actual_height).floor + 1
        right_current = pages_before + right_page_in_chapter

        total = total_pages

        {
          left: { current: left_current, total: total },
          right: { current: [right_current, total].min, total: total },
        }
      end
    end

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
      jump_to_chapter(@state.get(%i[reader toc_selected]))
    end

    def bookmark_down
      bookmarks_count = (@state.get(%i[reader bookmarks]) || []).length - 1
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: [@state.get(%i[reader bookmark_selected]) + 1,
                                                                                                   bookmarks_count].max))
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
      if pending_initial_calculation? && !preloaded_page_data?
        perform_initial_calculations_with_progress
      end
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

    # Expose controlled flag setters for the orchestrator
    attr_writer :defer_page_map

    def load_document
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
    end

    def load_data
      @state_controller.load_progress
      @state_controller.load_bookmarks
      @state_controller.refresh_annotations
    end

    def apply_pending_jump_if_present
      pending = @state.get(%i[reader pending_jump])
      return unless pending

      begin
        chapter_index = pending[:chapter_index] || pending['chapter_index']
        selection_range = pending[:selection_range] || pending['selection_range']
        edit_flag = pending[:edit] || pending['edit']
        ann = pending[:annotation] || pending['annotation']
        if chapter_index
          begin
            @dependencies.resolve(:navigation_service).jump_to_chapter(chapter_index)
          rescue StandardError
            # best-effort
          end
        end
        if selection_range
          @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionAction.new(selection_range))
        end
        if edit_flag && ann
          ann_text = ann[:text] || ann['text']
          ann_range = ann[:range] || ann['range']
          ann_id = ann[:id] || ann['id']
          ann_note = ann[:note] || ann['note']
          ann_chapter = ann[:chapter_index] || ann['chapter_index']
          # Switch to annotation editor with existing annotation payload
          @ui_controller.switch_mode(:annotation_editor,
                                     text: ann_text,
                                     range: ann_range,
                                     annotation: {
                                       'id' => ann_id,
                                       'text' => ann_text,
                                       'note' => ann_note,
                                       'chapter_index' => ann_chapter,
                                       'range' => ann_range,
                                     },
                                     chapter_index: chapter_index)
        end
      ensure
        @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: nil))
      end
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
      if @state.get(%i[config view_mode]) == :split
        split_pages = calculate_split_pages
        {
          type: :split,
          left: split_pages[:left],
          right: split_pages[:right],
        }
      else
        single_pages = calculate_current_pages
        {
          type: :single,
          current: single_pages[:current],
          total: single_pages[:total],
        }
      end
    rescue StandardError
      { type: :single, current: 0, total: 0 }
    end

    def initialize_page_calculations
      # left for compatibility; now handled in perform_initial_calculations_with_progress
    end

    def refresh_page_map(width, height)
      changed = size_changed?(width, height)
      if @state.get(%i[config page_numbering_mode]) == :dynamic && @page_calculator
        if changed
          @page_calculator.build_page_map(width, height, @doc, @state)
          clamped_index = [@state.get(%i[reader current_page_index]),
                           @page_calculator.total_pages - 1].min
          clamped_index = [0, clamped_index].max
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: clamped_index))
        end
      elsif changed
        update_page_map(width, height)
      end
    end

    def size_changed?(width, height)
      @state.terminal_size_changed?(width, height)
    end

    def build_page_map_in_background
      height, width = @terminal_service.size
      if @state.get(%i[config page_numbering_mode]) == :dynamic && @page_calculator
        @page_calculator.build_dynamic_map!(width, height, @doc, @state)
        @page_calculator.apply_pending_precise_restore!(@state)
      else
        # Absolute page numbering: delegate to PageCalculatorService
        @page_calculator.build_absolute_map!(width, height, @doc, @state)
      end
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

    def adjust_for_line_spacing(height)
      @layout_service.adjust_for_line_spacing(height, @state.get(%i[config line_spacing]))
    end

    def read_input_keys
      @terminal_service.read_keys_blocking(limit: 10)
    end

    def update_page_map(width, height)
      return if @doc.nil?

      # Delegate absolute pagination to the PageCalculatorService for consistency
      @page_calculator.build_absolute_map!(width, height, @doc, @state)
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
      view_mode = Domain::Selectors::ConfigSelectors.view_mode(@state)
      line_spacing = Domain::Selectors::ConfigSelectors.line_spacing(@state)
      key = EbookReader::Infrastructure::PaginationCache.layout_key(width, height, view_mode,
                                                                    line_spacing)
      if EbookReader::Infrastructure::PaginationCache.exists_for_document?(@doc, key)
        begin
          EbookReader::Infrastructure::PaginationCache.delete_for_document(@doc, key)
          @ui_controller.set_message('Pagination cache cleared')
        rescue StandardError
          @ui_controller.set_message('Failed to clear pagination cache')
        end
      else
        @ui_controller.set_message('No pagination cache for this layout')
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
      indices = entries.map(&:chapter_index).compact.uniq.sort
      if indices.empty?
        chapters_count = @doc&.chapters&.length.to_i
        @navigable_toc_indices = (0...chapters_count).to_a
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

    def background_worker
      @background_worker
    end
  end
end
