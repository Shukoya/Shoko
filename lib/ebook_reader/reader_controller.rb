# frozen_string_literal: true

require 'forwardable'
require_relative 'reader_modes/reading_mode'
require_relative 'reader_modes/help_mode'
require_relative 'reader_modes/toc_mode'
require_relative 'reader_modes/bookmarks_mode'
require_relative 'constants/ui_constants'
require_relative 'errors'
require_relative 'constants/messages'
require_relative 'helpers/reader_helpers'
require_relative 'services/state_service'
require_relative 'dynamic_page_calculator'
require_relative 'presenters/reader_presenter'
require_relative 'rendering/render_cache'
require_relative 'services/chapter_cache'
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
require_relative 'services/layout_service'

module EbookReader
  # Main reader interface for displaying EPUB content.
  #
  # This class coordinates the reading experience, managing the display,
  # navigation, bookmarks, and user input. It follows the Model-View-Controller
  # pattern where:
  # - Model: EPUBDocument and state management
  # - View: Renderers and display components
  # - Controller: Input handling and navigation
  #
  # @example Basic usage
  #   reader = MouseableReader.new("/path/to/book.epub")
  #   reader.run
  #
  # @attr_reader doc [EPUBDocument] The loaded EPUB document.
  # @attr_reader config [Config] The reader configuration.
  # @attr_reader page_manager [Services::PageManager] Manages page calculations.
  # @attr_reader path [String] The path to the EPUB file.
  # @attr_reader state [Core::GlobalState] The current state of the reader.
  class ReaderController
    extend Forwardable

    include Constants::UIConstants
    include Helpers::ReaderHelpers
    include DynamicPageCalculator
    include Input::KeyDefinitions::Helpers

    # All rendering is now component-based

    # All reader state should live in @state (Core::GlobalState)
    attr_reader :doc, :page_manager, :path, :state

    # Direct access to GlobalState config
    def config
      @state
    end

    # Delegate state accessors to @state for compatibility
    def_delegators :@state, :current_chapter, :current_chapter=,
                   :single_page, :single_page=, :current_page_index, :current_page_index=,
                   :left_page, :left_page=, :right_page, :right_page=

    def initialize(epub_path, _config = nil)
      @path = epub_path
      @state = Core::GlobalState.new
      @presenter = Presenters::ReaderPresenter.new(self, config)
      @selected_text = nil
      load_document
      @page_manager = Services::PageManager.new(@doc, config) if @doc

      # Initialize state service directly
      @state_service = Services::StateService.new(self)

      load_data
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @render_cache = Rendering::RenderCache.new
      @chapter_cache = Services::ChapterCache.new
      @last_rendered_state = {}
      build_component_layout
      setup_input_dispatcher

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
      Terminal.setup
      main_loop
    ensure
      Terminal.cleanup
    end

    # Component-based drawing
    def draw_screen
      height, width = Terminal.size

      # Update page maps on resize
      if size_changed?(width, height)
        refresh_page_map(width, height)
        @chapter_cache&.clear_cache_for_width(@state.last_width) if defined?(@chapter_cache)
      end

      # Prepare frame
      Terminal.start_frame
      @state.update_terminal_size(width, height)

      # Special-case full-screen modes that render their own UI
      if %i[annotation_editor annotations].include?(@state.mode) && @current_mode
        # Clear the frame area to avoid artifacts from reading view
        surface = Components::Surface.new(Terminal)
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface.fill(bounds, ' ')
        @current_mode.render(surface, bounds)
        Terminal.end_frame
        return
      end

      # Default: component-driven layout
      @state.rendered_lines = {}
      surface = Components::Surface.new(Terminal)
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

    def switch_mode(mode, **)
      @state.mode = mode

      case mode
      when :annotation_editor
        @current_mode = ReaderModes::AnnotationEditorMode.new(self, **)
      when :annotations
        @current_mode = ReaderModes::AnnotationsMode.new(self)
      when :read, :help, :toc, :bookmarks
        @current_mode = nil
      when :popup_menu
        # Popup handled separately via @state.popup_menu
      else
        @current_mode = nil
      end
      # Activate appropriate input bindings stack
      stack = [:read]
      stack << mode if mode && mode != :read

      @dispatcher.activate_stack(stack) if defined?(@dispatcher)
    end

    def scroll_down
      clear_selection!
      # Scroll down is implemented as page navigation for consistency
      next_page
    end

    def scroll_up
      clear_selection!
      # Scroll up is implemented as page navigation for consistency
      prev_page
    end

    def next_page
      clear_selection!

      # Use page manager if available and in dynamic mode
      if @page_manager && config.page_numbering_mode == :dynamic
        max_pages = @page_manager.total_pages

        @state.current_page_index = if config.view_mode == :split
                                      [@state.current_page_index + 2, max_pages - 1].min
                                    else
                                      [@state.current_page_index + 1, max_pages - 1].min
                                    end
      else
        # Fall back to absolute mode navigation
        @state.current_page_index = if config.view_mode == :split
                                      [@state.current_page_index + 2, @state.total_pages - 1].min
                                    else
                                      [@state.current_page_index + 1, @state.total_pages - 1].min
                                    end

        # Check if we need to advance to next chapter
        if (@state.current_page_index >= @state.total_pages - 1) && (@state.current_chapter < (@doc&.chapters&.length || 1) - 1)
          next_chapter
        end
      end

      force_redraw
    end

    def prev_page
      clear_selection!

      # Use page manager if available and in dynamic mode
      @state.current_page_index = if config.view_mode == :split
                                    [@state.current_page_index - 2, 0].max
                                  else
                                    [@state.current_page_index - 1, 0].max
                                  end
      if !(@page_manager && config.page_numbering_mode == :dynamic) && (@state.current_page_index <= 0) && @state.current_chapter.positive?
        # Fall back to absolute mode navigation

        # Check if we need to go to previous chapter
        prev_chapter
      end

      force_redraw
    end

    def go_to_start
      clear_selection!
      @state.current_chapter = 0
      @state.current_page_index = 0
      force_redraw
    end

    def go_to_end
      clear_selection!
      @state.current_chapter = (@doc&.chapters&.length || 1) - 1
      @state.current_page_index = @state.total_pages - 1
      force_redraw
    end

    def quit_to_menu
      save_progress
      @state.running = false
    end

    def quit_application
      save_progress
      Terminal.cleanup
      exit 0
    end

    def next_chapter
      clear_selection!
      max_chapter = (@doc&.chapters&.length || 1) - 1
      return unless @state.current_chapter < max_chapter

      @state.current_chapter += 1
      @state.current_page_index = 0
      force_redraw
    end

    def prev_chapter
      clear_selection!
      return unless @state.current_chapter.positive?

      @state.current_chapter -= 1
      @state.current_page_index = 0
      force_redraw
    end

    def add_bookmark
      clear_selection!
      # Basic bookmark functionality - store current position
      bookmark_data = {
        chapter: @state.current_chapter,
        page: @state.current_page_index,
        timestamp: Time.now,
      }

      # Add to bookmarks list in state
      current_bookmarks = @state.bookmarks || []
      current_bookmarks << bookmark_data
      @state.bookmarks = current_bookmarks

      set_message("Bookmark added at Chapter #{@state.current_chapter + 1}, Page #{@state.current_page}")
    end

    def toggle_view_mode
      clear_selection!
      @state.update(%i[config view_mode],
                    @state.get(%i[config view_mode]) == :split ? :single : :split)
      @state.save_config
      @state.last_width = 0
      @state.last_height = 0
      @state.dynamic_page_map = nil
      @state.dynamic_total_pages = 0
      @state.last_dynamic_width = 0
      @state.last_dynamic_height = 0

      # Force renderer recreation for view mode change
      content_component = @layout.instance_variable_get(:@children).find { |c| c.is_a?(Components::ContentComponent) }
      content_component&.instance_variable_set(:@view_renderer, nil)
      content_component&.instance_variable_set(:@needs_redraw, true)
    end

    def increase_line_spacing
      clear_selection!
      modes = %i[compact normal relaxed]
      current = modes.index(@state.get(%i[config line_spacing])) || 1
      return unless current < 2

      @state.update(%i[config line_spacing], modes[current + 1])
      @state.save_config
      @state.last_width = 0
    end

    def toggle_page_numbering_mode
      clear_selection!
      current_mode = @state.get(%i[config page_numbering_mode])
      new_mode = current_mode == :absolute ? :dynamic : :absolute
      @state.update(%i[config page_numbering_mode], new_mode)
      @state.save_config
      set_message("Page numbering: #{new_mode}")
    end

    def decrease_line_spacing
      clear_selection!
      modes = %i[compact normal relaxed]
      current = modes.index(@state.get(%i[config line_spacing])) || 1
      return unless current.positive?

      @state.update(%i[config line_spacing], modes[current - 1])
      @state.save_config
      @state.last_width = 0
    end

    def calculate_current_pages
      return { current: 0, total: 0 } unless @state.get(%i[config show_page_numbers])

      if @state.get(%i[config page_numbering_mode]) == :dynamic
        return { current: 0, total: 0 } unless @page_manager

        { current: @state.current_page_index + 1, total: @page_manager.total_pages }
      else
        height, width = Terminal.size
        _, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                      @state.get(%i[config view_mode]))
        actual_height = adjust_for_line_spacing(content_height)

        return { current: 0, total: 0 } if actual_height <= 0

        update_page_map(width, height) if size_changed?(width, height) || @state.page_map.empty?
        return { current: 0, total: 0 } unless @state.total_pages.positive?

        pages_before = @state.page_map[0...@state.current_chapter].sum
        line_offset = if @state.get(%i[config
                                       view_mode]) == :split
                        @state.left_page
                      else
                        @state.single_page
                      end
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter

        { current: current_global_page, total: @state.total_pages }
      end
    end

    def calculate_split_pages
      unless @state.get(%i[
                          config show_page_numbers
                        ])
        return { left: { current: 0, total: 0 },
                 right: { current: 0, total: 0 } }
      end

      if @state.get(%i[config page_numbering_mode]) == :dynamic
        unless @page_manager
          return { left: { current: 0, total: 0 },
                   right: { current: 0, total: 0 } }
        end

        left_page = @state.current_page_index + 1
        right_page = [left_page + 1, @page_manager.total_pages].min
        total = @page_manager.total_pages

        { left: { current: left_page, total: total }, right: { current: right_page, total: total } }
      else
        height, width = Terminal.size
        _, content_height = Services::LayoutService.calculate_metrics(width, height, :split)
        actual_height = adjust_for_line_spacing(content_height)

        if actual_height <= 0
          return { left: { current: 0, total: 0 },
                   right: { current: 0, total: 0 } }
        end

        update_page_map(width, height) if size_changed?(width, height) || @state.page_map.empty?
        unless @state.total_pages.positive?
          return { left: { current: 0, total: 0 },
                   right: { current: 0, total: 0 } }
        end

        pages_before = @state.page_map[0...@state.current_chapter].sum

        # Calculate left page
        left_line_offset = @state.left_page || 0
        left_page_in_chapter = (left_line_offset.to_f / actual_height).floor + 1
        left_current = pages_before + left_page_in_chapter

        # Calculate right page
        right_line_offset = @state.right_page || actual_height
        right_page_in_chapter = (right_line_offset.to_f / actual_height).floor + 1
        right_current = pages_before + right_page_in_chapter

        total = @state.total_pages

        {
          left: { current: left_current, total: total },
          right: { current: [right_current, total].min, total: total },
        }
      end
    end

    # Enhanced popup navigation handlers for direct key routing - MUST be public
    def handle_popup_navigation(key)
      return :pass unless @state.popup_menu

      result = @state.popup_menu.handle_key(key)

      if result && result[:type] == :selection_change
        draw_screen
        :handled
      else
        :pass
      end
    end

    def handle_popup_action_key(key)
      return :pass unless @state.popup_menu

      result = @state.popup_menu.handle_key(key)
      if result && result[:type] == :action
        handle_popup_action(result)
        draw_screen
        :handled
      else
        :pass
      end
    end

    def handle_popup_cancel(key)
      return :pass unless @state.popup_menu

      result = @state.popup_menu.handle_key(key)
      if result && result[:type] == :cancel
        cleanup_popup_state
        switch_mode(:read)
        draw_screen
        :handled
      else
        :pass
      end
    end

    def force_redraw
      content_component = @layout.instance_variable_get(:@children).find { |c| c.is_a?(Components::ContentComponent) }
      content_component&.instance_variable_set(:@needs_redraw, true)
    end

    def initialize_page_calculations
      return unless @doc

      # Get terminal size for initial page calculations
      width, height = Terminal.size

      if config.page_numbering_mode == :dynamic && @page_manager
        # Build page map for dynamic mode
        @page_manager.build_page_map(width, height)
      else
        # Update page map for absolute mode
        update_page_map(width, height)
      end
    end

    private

    # Hook for subclasses (MouseableReader) to clear any active selection/popup
    def clear_selection!
      # no-op in base controller
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
      @layout = if @state.sidebar_visible
                  # Use horizontal layout with sidebar + main content
                  Components::Layouts::Horizontal.new(@sidebar_component, @main_content_layout)
                else
                  # Use just the main content layout
                  @main_content_layout
                end
    end

    def create_view_model
      UI::ViewModels::ReaderViewModel.new(
        current_chapter: @state.current_chapter,
        total_chapters: @doc&.chapters&.length || 0,
        current_page: @state.current_page,
        total_pages: @state.total_pages,
        chapter_title: @doc&.get_chapter(@state.current_chapter)&.title || '',
        document_title: @doc&.title || '',
        view_mode: @state.get(%i[config view_mode]) || :split,
        sidebar_visible: @state.sidebar_visible,
        mode: @state.mode,
        message: @state.message,
        bookmarks: @state.bookmarks || [],
        show_page_numbers: @state.get(%i[config show_page_numbers]) || true,
        page_numbering_mode: @state.get(%i[config page_numbering_mode]) || :absolute,
        line_spacing: @state.get(%i[config line_spacing]) || :normal,
        language: @doc&.language || 'en',
        page_info: calculate_page_info_for_view_model
      )
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

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      setup_consolidated_reader_bindings
      @dispatcher.activate_stack([:read])
    end

    def setup_consolidated_reader_bindings
      # Use CommandFactory for standardized command creation
      @dispatcher.register_mode(:read, Commands::CommandFactory.create_bindings_for_mode(:read))
      @dispatcher.register_mode(:popup_menu, Commands::CommandFactory.create_bindings_for_mode(:popup_menu))

      # Keep legacy bindings for modes not yet converted
      register_help_bindings_new
      register_toc_bindings_new
      register_bookmarks_bindings_new
      register_annotation_editor_bindings_new
      register_annotations_list_bindings_new
    end

    def register_help_bindings_new
      bindings = { __default__: :exit_help }
      @dispatcher.register_mode(:help, bindings)
    end

    def register_toc_bindings_new
      bindings = {}

      # Exit TOC
      bindings['t'] = :exit_toc
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :exit_toc }

      # Navigation
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :toc_down }
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :toc_up }

      # Selection
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :toc_select }

      @dispatcher.register_mode(:toc, bindings)
    end

    def register_bookmarks_bindings_new
      bindings = {}

      # Exit bookmarks
      bindings['B'] = :exit_bookmarks
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :exit_bookmarks }

      # Navigation
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :bookmark_down }
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :bookmark_up }

      # Actions
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :bookmark_select }
      bindings['d'] = :delete_selected_bookmark

      @dispatcher.register_mode(:bookmarks, bindings)
    end

    def register_annotation_editor_bindings_new
      bindings = {}
      bindings[:__default__] = lambda { |ctx, key|
        mode = ctx.instance_variable_get(:@current_mode)
        if mode
          mode.handle_input(key)
          # Force redraw so the editor updates immediately
          ctx.draw_screen
        end
        :handled
      }
      @dispatcher.register_mode(:annotation_editor, bindings)
    end

    def register_annotations_list_bindings_new
      bindings = {}
      bindings[:__default__] = lambda { |ctx, key|
        mode = ctx.instance_variable_get(:@current_mode)
        if mode
          mode.handle_input(key)
          ctx.draw_screen
        end
        :handled
      }
      @dispatcher.register_mode(:annotations, bindings)
    end

    # ===== Rendering helpers migrated from legacy display =====
    def refresh_page_map(width, height)
      if @state.get(%i[config page_numbering_mode]) == :dynamic && @page_manager
        if size_changed?(width, height)
          @page_manager.build_page_map(width, height)
          @state.current_page_index = [@state.current_page_index, @page_manager.total_pages - 1].min
          @state.current_page_index = [0, @state.current_page_index].max
        end
      elsif size_changed?(width, height)
        update_page_map(width, height)
      end
    end

    def size_changed?(width, height)
      @state.terminal_size_changed?(width, height)
    end

    def adjust_for_line_spacing(height)
      Services::LayoutService.adjust_for_line_spacing(height, @state.get(%i[config line_spacing]))
    end

    def load_document
      @doc = EPUBDocument.new(@path)
    rescue StandardError => e
      @doc = create_error_document(e.message)
    end

    def load_data
      load_progress
      load_bookmarks
    end

    def main_loop
      draw_screen
      while @state.running
        keys = read_input_keys
        next if keys.empty?

        keys.each { |k| @dispatcher.handle_key(k) }
        draw_screen
      end
    end

    def handle_popup_menu_input(keys)
      return unless @state.popup_menu

      keys.each do |key|
        result = @state.popup_menu.handle_key(key)
        next unless result

        case result[:type]
        when :selection_change
          # Redraw only the popup area
          draw_screen
        when :action
          handle_popup_action(result)
          draw_screen # Full redraw after action
        when :cancel
          # Close the popup and return to reading mode
          cleanup_popup_state
          switch_mode(:read)
          draw_screen
        end
      end
    end

    def read_input_keys
      key = Terminal.read_key_blocking
      return [] unless key

      keys = [key]
      while (extra = Terminal.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end

    def capture_state
      page_value = if @state.get(%i[config page_numbering_mode]) == :dynamic
                     @state.current_page_index
                   elsif @state.get(%i[config
                                       view_mode]) == :split
                     @state.left_page
                   else
                     @state.single_page
                   end

      { chapter: @state.current_chapter, page: page_value, mode: @state.mode,
        message: @state.message }
    end

    def state_changed?(old_state)
      new_page = if @state.get(%i[config page_numbering_mode]) == :dynamic
                   @state.current_page_index
                 elsif @state.get(%i[config
                                     view_mode]) == :split
                   @state.left_page
                 else
                   @state.single_page
                 end

      old_state[:chapter] != @state.current_chapter ||
        old_state[:page] != new_page ||
        old_state[:mode] != @state.mode ||
        old_state[:message] != @state.message
    end

    def update_page_map(width, height)
      return if @doc.nil?

      # Generate a cache key based on all factors that affect page layout
      cache_key = "#{width}x#{height}-#{@state.get(%i[config
                                                      view_mode])}-#{@state.get(%i[config
                                                                                   line_spacing])}"

      # Use a cached map if it exists for the current configuration
      if @page_map_cache && @page_map_cache[:key] == cache_key
        @state.page_map = @page_map_cache[:map]
        @state.total_pages = @page_map_cache[:total]
        return
      end

      col_width, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                            @state.get(%i[config view_mode]))
      actual_height = adjust_for_line_spacing(content_height)
      return if actual_height <= 0

      calculate_page_map(col_width, actual_height, cache_key)
      @state.last_width = width
      @state.last_height = height
    end

    def calculate_page_map(col_width, actual_height, cache_key)
      @state.page_map = Array.new(@doc.chapter_count) do |idx|
        chapter = @doc.get_chapter(idx)
        lines = chapter&.lines || []
        wrapped = wrap_lines(lines, col_width)
        (wrapped.size.to_f / actual_height).ceil
      end
      @state.total_pages = @state.page_map.sum

      # Store the newly calculated map and its key in the cache
      @page_map_cache = { key: cache_key, map: @state.page_map, total: @state.total_pages }
    end

    def load_progress
      progress = @state_service.load_progress
      return unless progress

      @state.current_chapter = progress.fetch('chapter', 0)
      @state.single_page = progress.fetch('line_offset', 0)
    end

    def page_offsets=(offset)
      @state.page_offset = offset
      @state.single_page = offset
    end

    def save_progress
      @state_service.save_progress
    end

    def load_bookmarks
      @state.bookmarks = BookmarkManager.get(@path)
    end

    def extract_bookmark_text(chapter, line_offset)
      height, width = Terminal.size
      col_width, = Services::LayoutService.calculate_metrics(width, height,
                                                             @state.get(%i[config view_mode]))
      wrapped = wrap_lines(chapter.lines || [], col_width)
      text = wrapped[line_offset] || 'Bookmark'
      text.strip[0, 50]
    end

    def set_message(text, duration = 2)
      @state.message = text
      Thread.new do
        sleep duration
        @state.message = nil
      end
    end

    def create_error_document(error_msg)
      @presenter.error_document_for(error_msg)
    end

    def adjust_for_line_spacing(height)
      return 1 if height <= 0

      case @state.get(%i[config line_spacing])
      when :relaxed
        [height / 2, 1].max
      else # :compact, :normal
        height
      end
    end

    def open_toc
      switch_mode(:toc)
      @state.toc_selected = @state.current_chapter
    end

    def open_bookmarks
      switch_mode(:bookmarks)
      @state.bookmark_selected = 0
    end

    def open_annotations
      switch_mode(:annotations)
    end

    def show_help
      switch_mode(:help)
    end

    def exit_help
      switch_mode(:read)
    end

    def exit_toc
      switch_mode(:read)
    end

    def exit_bookmarks
      switch_mode(:read)
    end

    def toc_down
      @state.toc_selected = @state.toc_selected + 1
    end

    def toc_up
      @state.toc_selected = [@state.toc_selected - 1, 0].max
    end

    def toc_select
      jump_to_chapter(@state.toc_selected)
    end

    def bookmark_down
      bookmarks_count = (@state.bookmarks || []).length - 1
      @state.bookmark_selected = [@state.bookmark_selected + 1, bookmarks_count].max
    end

    def bookmark_up
      @state.bookmark_selected = [@state.bookmark_selected - 1, 0].max
    end

    def bookmark_select
      jump_to_bookmark
    end

    def handle_popup_key(key)
      if @state.popup_menu
        handle_popup_menu_input([key])
        :handled
      else
        :pass
      end
    end

    def handle_popup_action(action_data)
      # Handle both old string-based actions and new action objects
      action_type = action_data.is_a?(Hash) ? action_data[:action] : action_data

      case action_type
      when :create_annotation, 'Create Annotation'
        handle_create_annotation_action(action_data)
      when :copy_to_clipboard, 'Copy to Clipboard'
        handle_copy_to_clipboard_action(action_data)
      end

      cleanup_popup_state
    end

    def handle_create_annotation_action(action_data)
      selection_range = action_data.is_a?(Hash) ? action_data[:data][:selection_range] : @state.selection
      switch_mode(:read)
      switch_mode(:annotation_editor,
                  text: @selected_text,
                  range: selection_range,
                  chapter_index: @state.current_chapter)
    end

    def handle_copy_to_clipboard_action(_action_data)
      if Services::ClipboardService.available?
        success = Services::ClipboardService.copy_with_feedback(@selected_text, lambda { |msg|
          set_message(msg)
        })
        set_message('Failed to copy to clipboard') unless success
      else
        set_message('Copy to clipboard not available')
      end
      switch_mode(:read)
    end

    def cleanup_popup_state
      @state.popup_menu = nil
      @mouse_handler&.reset
      @state.selection = nil
    end

    def reset_pages
      clear_selection!
    end

    def position_at_chapter_end
      # Position at the end of current chapter
      @state.current_page_index = @state.total_pages - 1
    end

    def save_progress
      @state_service.save_progress
    end

    public

    # Legacy delegators removed; input handling is centralized via
    # Input::Dispatcher and renderer-driven drawing.

    def jump_to_chapter(chapter_index)
      clear_selection!
      @state.current_chapter = chapter_index
      save_progress
      @state.mode = :read
    end

    # Bookmarks input handled via centralized handler as well

    def handle_empty_bookmarks_input(key)
      @input_handler.handle_empty_bookmarks_input(key)
    end

    def jump_to_bookmark
      bookmark = @state.bookmarks[@state.bookmark_selected]
      return unless bookmark

      @state.current_chapter = bookmark.chapter_index
      self.page_offsets = bookmark.line_offset
      save_progress
      @state.mode = :read
    end

    def delete_selected_bookmark
      bookmark = @state.bookmarks[@state.bookmark_selected]
      return unless bookmark

      BookmarkManager.delete(@path, bookmark)
      load_bookmarks
      if @state.bookmarks.any?
        @state.bookmark_selected = [@state.bookmark_selected, @state.bookmarks.length - 1].min
      end
      set_message(Constants::Messages::BOOKMARK_DELETED)
    end

    def reset_pages
      clear_selection!
    end

    def position_at_chapter_end
      # Position at the end of current chapter
      @state.current_page_index = @state.total_pages - 1
    end
  end
end
