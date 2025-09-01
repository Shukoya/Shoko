# frozen_string_literal: true

require 'forwardable'
require_relative 'reader_modes/help_mode'
require_relative 'reader_modes/toc_mode'
require_relative 'reader_modes/bookmarks_mode'
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
require_relative 'components/popup_overlay_component'
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
      @chapter_cache = @dependencies.resolve(:chapter_cache) if @dependencies.registered?(:chapter_cache)
      @layout_service = @dependencies.resolve(:layout_service)
      @clipboard_service = @dependencies.resolve(:clipboard_service)
      @terminal_service = @dependencies.resolve(:terminal_service)

      # Load document before creating controllers that depend on it
      load_document
      # Expose current book path in state for downstream services/screens
      @state.update({[:reader, :book_path] => @path})
      
      # Initialize focused controllers with proper dependencies including document
      @navigation_controller = Controllers::NavigationController.new(@state, @doc, @page_calculator, @dependencies)
      @ui_controller = Controllers::UIController.new(@state, @dependencies)
      @state_controller = Controllers::StateController.new(@state, @doc, epub_path, @dependencies)
      @input_controller = Controllers::InputController.new(@state, @dependencies)

      # Register controllers in the dependency container for components that resolve them
      @dependencies.register(:navigation_controller, @navigation_controller)
      @dependencies.register(:ui_controller, @ui_controller)
      @dependencies.register(:state_controller, @state_controller)
      @dependencies.register(:input_controller, @input_controller)

      @presenter = Presenters::ReaderPresenter.new(self, @state)

      # Load saved data
      load_data
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @render_cache = Rendering::RenderCache.new
      @last_rendered_state = {}

      # Build UI components
      build_component_layout
      @input_controller.setup_input_dispatcher(self)

      # Initialize page calculations for navigation
      initialize_page_calculations

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
        @chapter_cache&.clear_cache_for_width(@state.get([:reader, :last_width])) if defined?(@chapter_cache)
      end

      # Prepare frame
      @terminal_service.start_frame
      @state.update_terminal_size(width, height)

      # Special-case full-screen modes that render their own UI
      if %i[annotation_editor annotations].include?(@state.get([:reader, :mode])) && @ui_controller.current_mode
        # Clear the frame area to avoid artifacts from reading view
        surface = @terminal_service.create_surface
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface.fill(bounds, ' ')
        @ui_controller.current_mode.render(surface, bounds)
        @terminal_service.end_frame
        return
      end

      # Default: component-driven layout
      @state.update({[:reader, :rendered_lines] => {}})
      surface = @terminal_service.create_surface
      root_bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      @layout.render(surface, root_bounds)
      # Render overlay components (e.g., popup menus) last
      @overlay ||= Components::PopupOverlayComponent.new(self)
      @overlay.render(surface, root_bounds)
      # NOTE: MouseableReader will call Terminal.end_frame after overlays
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

        { current: @state.get([:reader, :current_page_index]) + 1, total: @page_calculator.total_pages }
      else
        height, width = @terminal_service.size
        _, content_height = @layout_service.calculate_metrics(width, height, @state.get(%i[config view_mode]))
        actual_height = adjust_for_line_spacing(content_height)

        return { current: 0, total: 0 } if actual_height <= 0

        update_page_map(width, height) if size_changed?(width, height) || @state.get([:reader, :page_map]).empty?
        return { current: 0, total: 0 } unless @state.get([:reader, :total_pages]).positive?

        pages_before = @state.get([:reader, :page_map])[0...@state.get([:reader, :current_chapter])].sum
        line_offset = if @state.get(%i[config view_mode]) == :split
                        @state.get([:reader, :left_page])
                      else
                        @state.get([:reader, :single_page])
                      end
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter

        { current: current_global_page, total: @state.get([:reader, :total_pages]) }
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

        left_page = @state.get([:reader, :current_page_index]) + 1
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

        update_page_map(width, height) if size_changed?(width, height) || @state.get([:reader, :page_map]).empty?
        unless @state.get([:reader, :total_pages]).positive?
          return { left: { current: 0, total: 0 }, right: { current: 0, total: 0 } }
        end

        pages_before = @state.get([:reader, :page_map])[0...@state.get([:reader, :current_chapter])].sum

        # Calculate left page
        left_line_offset = @state.get([:reader, :left_page]) || 0
        left_page_in_chapter = (left_line_offset.to_f / actual_height).floor + 1
        left_current = pages_before + left_page_in_chapter

        # Calculate right page
        right_line_offset = @state.get([:reader, :right_page]) || actual_height
        right_page_in_chapter = (right_line_offset.to_f / actual_height).floor + 1
        right_current = pages_before + right_page_in_chapter

        total = @state.get([:reader, :total_pages])

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
      @state.update({[:reader, :toc_selected] => @state.get([:reader, :toc_selected]) + 1})
    end

    def toc_up
      @state.update({[:reader, :toc_selected] => [@state.get([:reader, :toc_selected]) - 1, 0].max})
    end

    def toc_select
      jump_to_chapter(@state.get([:reader, :toc_selected]))
    end

    def bookmark_down
      bookmarks_count = (@state.get([:reader, :bookmarks]) || []).length - 1
      @state.update({[:reader, :bookmark_selected] => [@state.get([:reader, :bookmark_selected]) + 1, bookmarks_count].max})
    end

    def bookmark_up
      @state.update({[:reader, :bookmark_selected] => [@state.get([:reader, :bookmark_selected]) - 1, 0].max})
    end

    def bookmark_select
      jump_to_bookmark
    end

    def create_view_model
      UI::ViewModels::ReaderViewModel.new(
        current_chapter: @state.get([:reader, :current_chapter]),
        total_chapters: @doc&.chapters&.length || 0,
        current_page: @state.get([:reader, :current_page]),
        total_pages: @state.get([:reader, :total_pages]),
        chapter_title: @doc&.get_chapter(@state.get([:reader, :current_chapter]))&.title || '',
        document_title: @doc&.title || '',
        view_mode: @state.get(%i[config view_mode]) || :split,
        sidebar_visible: @state.get([:reader, :sidebar_visible]),
        mode: @state.get([:reader, :mode]),
        message: @state.get([:reader, :message]),
        bookmarks: @state.get([:reader, :bookmarks]) || [],
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
    end

    def load_data
      @state_controller.load_progress
      @state_controller.load_bookmarks
      @state_controller.refresh_annotations
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
      @layout = if @state.get([:reader, :sidebar_visible])
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
      return unless @doc

      # Get terminal size for initial page calculations
      height, width = @terminal_service.size

      if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
        # Build page map for dynamic mode
        @page_calculator.build_page_map(width, height, @doc, @state)
      else
        # Update page map for absolute mode
        update_page_map(width, height)
      end
    end

    def refresh_page_map(width, height)
      if @state.get(%i[config page_numbering_mode]) == :dynamic && @page_calculator
        if size_changed?(width, height)
          @page_calculator.build_page_map(width, height, @doc, @state)
          clamped_index = [@state.get([:reader, :current_page_index]), @page_calculator.total_pages - 1].min
          clamped_index = [0, clamped_index].max
          @state.update({[:reader, :current_page_index] => clamped_index})
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
      cache_key = "#{width}x#{height}-#{@state.get(%i[config view_mode])}-#{@state.get(%i[config line_spacing])}"

      # Use a cached map if it exists for the current configuration
      if @page_map_cache && @page_map_cache[:key] == cache_key
        @state.update({[:reader, :page_map] => @page_map_cache[:map]})
        @state.update({[:reader, :total_pages] => @page_map_cache[:total]})
        return
      end

      col_width, content_height = @layout_service.calculate_metrics(width, height, @state.get(%i[config view_mode]))
      actual_height = adjust_for_line_spacing(content_height)
      return if actual_height <= 0

      calculate_page_map(col_width, actual_height, cache_key)
      @state.update({[:reader, :last_width] => width})
      @state.update({[:reader, :last_height] => height})
    end

    def calculate_page_map(col_width, actual_height, cache_key)
      page_map = Array.new(@doc.chapter_count) do |idx|
        chapter = @doc.get_chapter(idx)
        lines = chapter&.lines || []
        wrapped = wrap_lines(lines, col_width)
        (wrapped.size.to_f / actual_height).ceil
      end
      @state.update({[:reader, :page_map] => page_map})
      @state.update({[:reader, :total_pages] => page_map.sum})

      # Store the newly calculated map and its key in the cache
      @page_map_cache = { key: cache_key, map: @state.get([:reader, :page_map]), total: @state.get([:reader, :total_pages]) }
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
