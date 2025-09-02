# frozen_string_literal: true

require 'forwardable'
# Legacy reader modes removed (help/toc/bookmarks now rendered via components)
require_relative 'constants/ui_constants'
require_relative 'errors'
require_relative 'constants/messages'
require_relative 'helpers/reader_helpers'
require_relative 'presenters/reader_presenter'
require_relative 'rendering/render_cache'
require_relative 'components/surface'
require_relative 'components/rect'
require_relative 'components/layouts/vertical'
require_relative 'components/layouts/horizontal'
require_relative 'components/header_component'
require_relative 'components/content_component'
require_relative 'components/footer_component'
require_relative 'components/tooltip_overlay_component'
require_relative 'components/sidebar_panel_component'
require_relative 'input/dispatcher'

module EbookReader
  # Coordinator class for the reading experience.
  #
  # This refactored ReaderController now delegates responsibilities to focused controllers:
  # - NavigationController: handles page/chapter navigation
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
    include Helpers::ReaderHelpers
    include Input::KeyDefinitions::Helpers

    attr_reader :doc, :path, :state, :page_calculator, :dependencies

    # Delegate to focused controllers
    def_delegators :@navigation_controller, :next_page, :prev_page, :next_chapter, :prev_chapter,
                   :go_to_start, :go_to_end, :jump_to_chapter, :scroll_down, :scroll_up

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

      # Initialize document and services first
      @page_calculator = @dependencies.resolve(:page_calculator)
      if @dependencies.registered?(:chapter_cache)
        @chapter_cache = @dependencies.resolve(:chapter_cache)
      end
      @layout_service = @dependencies.resolve(:layout_service)
      @clipboard_service = @dependencies.resolve(:clipboard_service)
      @terminal_service = @dependencies.resolve(:terminal_service)
      if @dependencies.registered?(:wrapping_service)
        @wrapping_service = @dependencies.resolve(:wrapping_service)
      end

      # Load document before creating controllers that depend on it
      load_document
      # Expose current book path in state for downstream services/screens
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(book_path: @path))

      # Initialize focused controllers with proper dependencies including document
      @navigation_controller = Controllers::NavigationController.new(@state, @doc,
                                                                     @page_calculator, @dependencies)
      @ui_controller = Controllers::UIController.new(@state, @dependencies)
      @state_controller = Controllers::StateController.new(@state, @doc, epub_path,
                                                           @dependencies)
      @input_controller = Controllers::InputController.new(@state, @dependencies)

      # Register controllers in the dependency container for components that resolve them
      @dependencies.register(:navigation_controller, @navigation_controller)
      @dependencies.register(:ui_controller, @ui_controller)
      @dependencies.register(:state_controller, @state_controller)
      @dependencies.register(:input_controller, @input_controller)
      # Expose reader controller for components/controllers needing cleanup hooks
      @dependencies.register(:reader_controller, self)

      @presenter = Presenters::ReaderPresenter.new(self, @state)

      # Load saved data
      load_data
      apply_pending_jump_if_present
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @render_cache = Rendering::RenderCache.new
      @last_rendered_state = {}

      # Build UI components
      build_component_layout
      @input_controller.setup_input_dispatcher(self)

      # Build unified overlay component (used for highlights and popups)
      coord = @dependencies.resolve(:coordinate_service)
      @overlay = Components::TooltipOverlayComponent.new(self, coordinate_service: coord)

      # Defer heavy page calculations until after terminal setup
      @pending_initial_calculation = true

      # Observe sidebar visibility changes to rebuild layout
      @state.add_observer(self, %i[reader sidebar_visible])
    end

    # Observer callback for state changes
    def state_changed(path, _old_value, _new_value)
      return unless path == %i[reader sidebar_visible]

      rebuild_root_layout
    end

    def run
      @terminal_service.setup
      if @pending_initial_calculation
        unless preloaded_page_data?
          # Build silently if needed but avoid showing a loading overlay
          height, width = @terminal_service.size
          if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
            @page_calculator.build_page_map(width, height, @doc, @state)
          else
            update_page_map(width, height)
          end
        end
        @pending_initial_calculation = false
      end
      main_loop
    ensure
      @terminal_service.cleanup
    end

    # Component-based drawing
    def draw_screen
      height, width = @terminal_service.size

      # Update page maps on resize
      if size_changed?(width, height)
        refresh_page_map(width, height)
        if defined?(@chapter_cache)
          @chapter_cache&.clear_cache_for_width(@state.get(%i[reader
                                                              last_width]))
        end
      end

      # Prepare frame
      @terminal_service.start_frame
      @state.update_terminal_size(width, height)

      # Special-case full-screen modes that render their own UI
      if %i[annotation_editor].include?(@state.get(%i[reader mode])) && @ui_controller.current_mode
        # Clear the frame area to avoid artifacts from reading view
        surface = @terminal_service.create_surface
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface.fill(bounds, ' ')
        @ui_controller.current_mode.render(surface, bounds)
        @terminal_service.end_frame
        return
      end

      # Default: component-driven layout
      @state.dispatch(EbookReader::Domain::Actions::ClearRenderedLinesAction.new)
      surface = @terminal_service.create_surface
      root_bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      @layout.render(surface, root_bounds)
      # Render overlay last (highlights, popup menu)
      @overlay.render(surface, root_bounds)
      @terminal_service.end_frame
    end

    # Partial refresh hook for subclasses.
    # By default, re-renders the current screen without ending the frame.
    # MouseableReader layers selection/annotation highlights on top and then ends the frame.
    def refresh_highlighting
      draw_screen
    end

    def force_redraw
      @content_component&.instance_variable_set(:@needs_redraw, true)
    end

    # Main application loop
    def main_loop
      draw_screen
      while EbookReader::Domain::Selectors::ReaderSelectors.running?(@state)
        keys = read_input_keys
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

      if @state.get(%i[config page_numbering_mode]) == :dynamic
        return { current: 0, total: 0 } unless @page_calculator

        { current: @state.get(%i[reader current_page_index]) + 1,
          total: @page_calculator.total_pages }
      else
        height, width = @terminal_service.size
        _, content_height = @layout_service.calculate_metrics(width, height,
                                                              @state.get(%i[config view_mode]))
        actual_height = adjust_for_line_spacing(content_height)

        return { current: 0, total: 0 } if actual_height <= 0

        update_page_map(width, height) if size_changed?(width,
                                                        height) || @state.get(%i[reader
                                                                                 page_map]).empty?
        return { current: 0, total: 0 } unless @state.get(%i[reader total_pages]).positive?

        pages_before = @state.get(%i[reader
                                     page_map])[0...@state.get(%i[reader current_chapter])].sum
        line_offset = if @state.get(%i[config view_mode]) == :split
                        @state.get(%i[reader left_page])
                      else
                        @state.get(%i[reader single_page])
                      end
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter

        { current: current_global_page, total: @state.get(%i[reader total_pages]) }
      end
    end

    def calculate_split_pages
      unless @state.get(%i[config show_page_numbers])
        return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
      end

      if @state.get(%i[config page_numbering_mode]) == :dynamic
        unless @page_calculator
          return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
        end

        left_page = @state.get(%i[reader current_page_index]) + 1
        right_page = [left_page + 1, @page_calculator.total_pages].min
        total = @page_calculator.total_pages

        { left: { current: left_page, total: total }, right: { current: right_page, total: total } }
      else
        height, width = @terminal_service.size
        _, content_height = @layout_service.calculate_metrics(width, height, :split)
        actual_height = adjust_for_line_spacing(content_height)

        if actual_height <= 0
          return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
        end

        update_page_map(width, height) if size_changed?(width,
                                                        height) || @state.get(%i[reader
                                                                                 page_map]).empty?
        unless @state.get(%i[reader total_pages]).positive?
          return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
        end

        pages_before = @state.get(%i[reader
                                     page_map])[0...@state.get(%i[reader current_chapter])].sum

        # Calculate left page
        left_line_offset = @state.get(%i[reader left_page]) || 0
        left_page_in_chapter = (left_line_offset.to_f / actual_height).floor + 1
        left_current = pages_before + left_page_in_chapter

        # Calculate right page
        right_line_offset = @state.get(%i[reader right_page]) || actual_height
        right_page_in_chapter = (right_line_offset.to_f / actual_height).floor + 1
        right_current = pages_before + right_page_in_chapter

        total = @state.get(%i[reader total_pages])

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
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(toc_selected: @state.get(%i[
                                                                                                          reader toc_selected
                                                                                                        ]) + 1))
    end

    def toc_up
      @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(toc_selected: [
        @state.get(%i[reader toc_selected]) - 1, 0
      ].max))
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
      UI::ViewModels::ReaderViewModel.new(
        current_chapter: @state.get(%i[reader current_chapter]),
        total_chapters: @doc&.chapters&.length || 0,
        current_page: @state.get(%i[reader current_page]),
        total_pages: @state.get(%i[reader total_pages]),
        chapter_title: @doc&.get_chapter(@state.get(%i[reader current_chapter]))&.title || '',
        document_title: @doc&.title || '',
        view_mode: @state.get(%i[config view_mode]) || :split,
        sidebar_visible: @state.get(%i[reader sidebar_visible]),
        mode: @state.get(%i[reader mode]),
        message: @state.get(%i[reader message]),
        bookmarks: @state.get(%i[reader bookmarks]) || [],
        show_page_numbers: @state.get(%i[config show_page_numbers]) || true,
        page_numbering_mode: @state.get(%i[config page_numbering_mode]) || :absolute,
        line_spacing: @state.get(%i[config line_spacing]) || :normal,
        language: @doc&.language || 'en',
        page_info: calculate_page_info_for_view_model
      )
    end

    private

    def load_document
      document_service = Infrastructure::DocumentService.new(@path)
      @doc = document_service.load_document

      # Register document in dependency container for services to access
      @dependencies.register(:document, @doc)
      # Expose chapter count for navigation service logic
      begin
        @state.update({ %i[reader total_chapters] => @doc&.chapter_count || 0 })
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
        @navigation_controller.jump_to_chapter(chapter_index) if chapter_index
        if selection_range
          @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionAction.new(selection_range))
        end
        if edit_flag && ann
          # Ensure selection exists for editor context
          if selection_range
            @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionAction.new(selection_range))
          end
          # Switch to annotation editor with existing annotation payload
          @ui_controller.switch_mode(:annotation_editor,
                                     text: ann[:text] || ann['text'],
                                     range: ann[:range] || ann['range'],
                                     annotation: {
                                       'id' => ann[:id] || ann['id'],
                                       'text' => ann[:text] || ann['text'],
                                       'note' => ann[:note] || ann['note'],
                                       'chapter_index' => ann[:chapter_index] || ann['chapter_index'],
                                       'range' => ann[:range] || ann['range'],
                                     },
                                     chapter_index: chapter_index)
        end
      ensure
        @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: nil))
      end
    end

    def build_component_layout
      @header_component = Components::HeaderComponent.new(method(:create_view_model))
      @content_component = Components::ContentComponent.new(self)
      @footer_component = Components::FooterComponent.new(method(:create_view_model))
      @sidebar_component = Components::SidebarPanelComponent.new(self)

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
      if @state.get(%i[config page_numbering_mode]) == :dynamic && @page_calculator
        if size_changed?(width, height)
          @page_calculator.build_page_map(width, height, @doc, @state)
          clamped_index = [@state.get(%i[reader current_page_index]),
                           @page_calculator.total_pages - 1].min
          clamped_index = [0, clamped_index].max
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: clamped_index))
        end
      elsif size_changed?(width, height)
        update_page_map(width, height)
      end
    end

    def size_changed?(width, height)
      @state.terminal_size_changed?(width, height)
    end

    def adjust_for_line_spacing(height)
      @layout_service.adjust_for_line_spacing(height, @state.get(%i[config line_spacing]))
    end

    def read_input_keys
      key = @terminal_service.read_key_blocking
      return [] unless key

      keys = [key]
      while (extra = @terminal_service.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end

    def update_page_map(width, height)
      return if @doc.nil?

      # Generate a cache key based on all factors that affect page layout
      cache_key = "#{width}x#{height}-#{@state.get(%i[config
                                                      view_mode])}-#{@state.get(%i[config
                                                                                   line_spacing])}"

      # Use a cached map if it exists for the current configuration
      if @page_map_cache && @page_map_cache[:key] == cache_key
        @state.update({ %i[reader page_map] => @page_map_cache[:map],
                        %i[reader total_pages] => @page_map_cache[:total] })
        return
      end

      col_width, content_height = @layout_service.calculate_metrics(width, height,
                                                                    @state.get(%i[config view_mode]))
      actual_height = adjust_for_line_spacing(content_height)
      return if actual_height <= 0

      calculate_page_map(col_width, actual_height, cache_key)
      @state.update({ %i[reader last_width] => width, %i[reader last_height] => height })
    end

    def calculate_page_map(col_width, actual_height, cache_key)
      page_map = Array.new(@doc.chapter_count) do |idx|
        chapter = @doc.get_chapter(idx)
        lines = chapter&.lines || []
        wrapped = wrap_lines(lines, col_width)
        (wrapped.size.to_f / actual_height).ceil
      end
      @state.update({ %i[reader page_map] => page_map, %i[reader total_pages] => page_map.sum })

      # Store the newly calculated map and its key in the cache
      @page_map_cache = { key: cache_key, map: @state.get(%i[reader page_map]),
                          total: @state.get(%i[reader total_pages]) }
    end

    # Perform initial heavy page calculations with a visual progress overlay
    def perform_initial_calculations_with_progress
      return unless @doc

      height, width = @terminal_service.size
      @state.update({ %i[ui loading_active] => true,
                      %i[ui loading_message] => 'Opening book…',
                      %i[ui loading_progress] => 0.0 })

      render_loading_overlay

      if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
        # Dynamic: use page calculator with progress callback
        @page_calculator.build_page_map(width, height, @doc, @state) do |done, total|
          @state.update({ %i[ui loading_progress] => (done.to_f / [total, 1].max) })
          render_loading_overlay
        end
        # Sync total pages to state for view model
        @state.update({ %i[reader total_pages] => @page_calculator.total_pages })
      else
        # Absolute: compute per-chapter and update progress
        col_width, content_height = @layout_service.calculate_metrics(width, height,
                                                                      @state.get(%i[config view_mode]))
        actual_height = adjust_for_line_spacing(content_height)
        total = @doc.chapter_count
        page_map = []
        total.times do |idx|
          chapter = @doc.get_chapter(idx)
          lines = chapter&.lines || []
          wrapped = wrap_lines(lines, col_width)
          page_map << (wrapped.size.to_f / [actual_height, 1].max).ceil
          @state.update({ %i[ui loading_progress] => ((idx + 1).to_f / [total, 1].max) })
          render_loading_overlay
        end
        @state.update({ %i[reader page_map] => page_map, %i[reader total_pages] => page_map.sum,
                        %i[reader last_width] => width, %i[reader last_height] => height })
        @page_map_cache = { key: "#{width}x#{height}-#{@state.get(%i[config view_mode])}-#{@state.get(%i[config line_spacing])}",
                            map: page_map, total: page_map.sum }
      end

      # Clear loading state and render once before entering main loop
      @state.update({ %i[ui loading_active] => false, %i[ui loading_message] => nil })
      draw_screen
    rescue StandardError
      # Best-effort; ensure we clear loading state to avoid a stuck overlay
      @state.update({ %i[ui loading_active] => false })
    end

    def render_loading_overlay
      height, width = @terminal_service.size
      @terminal_service.start_frame
      surface = @terminal_service.create_surface
      bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)

      # Ultra-minimal progress bar near the top, single-row height
      bar_row = [2, height - 1].min
      bar_col = 2
      bar_width = [[width - (bar_col + 1), 10].max, width - bar_col].min

      progress = (@state.get(%i[ui loading_progress]) || 0.0).to_f.clamp(0.0, 1.0)
      filled = (bar_width * progress).round

      green_fg = Terminal::ANSI::BRIGHT_GREEN
      grey_fg  = Terminal::ANSI::GRAY
      reset    = Terminal::ANSI::RESET

      # Use thin line glyphs with foreground colors to avoid background bleed
      track = if bar_width.positive?
                (green_fg + ('━' * filled)) + (grey_fg + ('━' * (bar_width - filled))) + reset
              else
                ''
              end
      surface.write(bounds, bar_row, bar_col, track)

      @terminal_service.end_frame
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
      # Fallback to helper behavior if service missing (tests/dev only)
      super
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
  end
end
