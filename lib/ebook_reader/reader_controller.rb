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
require_relative 'concerns/input_handler'
require_relative 'core/reader_state'
require_relative 'services/navigation_service'
require_relative 'services/bookmark_service'
require_relative 'services/state_service'
require_relative 'dynamic_page_calculator'
require_relative 'presenters/reader_presenter'
require_relative 'rendering/render_cache'
require_relative 'services/chapter_cache'
require_relative 'components/surface'
require_relative 'components/rect'
require_relative 'components/layouts/vertical'
require_relative 'components/header_component'
require_relative 'components/content_component'
require_relative 'components/footer_component'
require_relative 'components/popup_overlay_component'
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
  #   reader = Reader.new("/path/to/book.epub")
  #   reader.run
  #
  # @example With custom configuration
  #   config = Config.new
  #   config.view_mode = :single
  #   reader = Reader.new("/path/to/book.epub", config)
  #   reader.run
  #
  # @attr_reader doc [EPUBDocument] The loaded EPUB document.
  # @attr_reader config [Config] The reader configuration.
  # @attr_reader page_manager [Services::PageManager] Manages page calculations.
  # @attr_reader path [String] The path to the EPUB file.
  # @attr_reader state [Core::ReaderState] The current state of the reader.
  class ReaderController
    extend Forwardable

    include Constants::UIConstants
    include Helpers::ReaderHelpers
    include Concerns::InputHandler
    include DynamicPageCalculator
    include Input::KeyDefinitions::Helpers

    # All rendering is now component-based

    # All reader state should live in @state (Core::ReaderState)
    attr_reader :doc, :config, :page_manager, :path, :state

    # Delegate state accessors to @state for compatibility
    def_delegators :@state, :current_chapter, :current_chapter=,
                   :left_page, :left_page=, :right_page, :right_page=,
                   :single_page, :single_page=, :current_page_index, :current_page_index=

    def initialize(epub_path, config = Config.new)
      @path = epub_path
      @config = config
      @state = Core::ReaderState.new
      @presenter = Presenters::ReaderPresenter.new(self, @config)
      @selected_text = nil
      load_document
      @page_manager = Services::PageManager.new(@doc, @config) if @doc

      # Initialize service registry for dependency injection
      Services::ServiceRegistry.initialize_services(self)
      @navigation_service = Services::ServiceRegistry.navigation
      @bookmark_service = Services::ServiceRegistry.bookmark
      @state_service = Services::ServiceRegistry.state

      load_data
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @render_cache = Rendering::RenderCache.new
      @chapter_cache = Services::ChapterCache.new
      @last_rendered_state = {}
      build_component_layout
      setup_input_dispatcher
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
        @current_mode.draw(height, width)
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
      return if @config.page_numbering_mode == :dynamic

      if @config.view_mode == :split
        @state.left_page = [@state.left_page + 1, @max_page || 0].min
        @state.right_page = [@state.right_page + 1, @max_page || 0].min
      else
        @state.single_page = [@state.single_page + 1, @max_page || 0].min
      end
    end

    def scroll_up
      clear_selection!
      return if @config.page_numbering_mode == :dynamic

      if @config.view_mode == :split
        @state.left_page = [@state.left_page - 1, 0].max
        @state.right_page = [@state.right_page - 1, 0].max
      else
        @state.single_page = [@state.single_page - 1, 0].max
      end
    end

    def next_page
      clear_selection!
      if @config.page_numbering_mode == :dynamic
        next_page_dynamic
      else
        next_page_absolute
      end
    end

    def prev_page
      clear_selection!
      if @config.page_numbering_mode == :dynamic
        prev_page_dynamic
      else
        prev_page_absolute
      end
    end

    def next_page_dynamic
      clear_selection!
      return unless @page_manager

      return unless @state.current_page_index < @page_manager.total_pages - 1

      @state.current_page_index += 1
      update_chapter_from_page_index
    end

    def prev_page_dynamic
      clear_selection!
      return unless @page_manager

      return unless @state.current_page_index.positive?

      @state.current_page_index -= 1
      update_chapter_from_page_index
    end

    def next_page_absolute
      clear_selection!
      @navigation_service.next_page_absolute
    end

    def prev_page_absolute
      clear_selection!
      return if @state.current_chapter.zero? && @state.single_page.zero? && @state.left_page.zero?

      if @config.view_mode == :split
        if @state.left_page.positive?
          @state.right_page = @state.left_page
          @state.left_page = [@state.left_page - (Terminal.size[0] - 2), 0].max
        elsif @state.current_chapter.positive?
          @state.current_chapter -= 1
          position_at_chapter_end
        end
      elsif @state.single_page.positive?
        @state.single_page = [@state.single_page - (Terminal.size[0] - 2), 0].max
      elsif @state.current_chapter.positive?
        @state.current_chapter -= 1
        position_at_chapter_end
      end
    end

    def update_chapter_from_page_index
      page_data = @page_manager.get_page(@state.current_page_index)
      return unless page_data

      @state.current_chapter = page_data[:chapter_index]
    end

    def go_to_start
      clear_selection!
      reset_pages
    end

    def go_to_end
      clear_selection!
      @navigation_service.go_to_end
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
      @navigation_service.next_chapter
    end

    def prev_chapter
      clear_selection!
      @navigation_service.prev_chapter
    end

    def add_bookmark
      clear_selection!
      @bookmark_service.add_bookmark
    end

    def toggle_view_mode
      clear_selection!
      @config.view_mode = @config.view_mode == :split ? :single : :split
      @config.save
      @state.last_width = 0
      @state.last_height = 0
      @state.dynamic_page_map = nil
      @state.dynamic_total_pages = 0
      @state.last_dynamic_width = 0
      @state.last_dynamic_height = 0
      reset_pages
    end

    def increase_line_spacing
      clear_selection!
      modes = %i[compact normal relaxed]
      current = modes.index(@config.line_spacing) || 1
      return unless current < 2

      @config.line_spacing = modes[current + 1]
      @config.save
      @state.last_width = 0
    end

    def toggle_page_numbering_mode
      clear_selection!
      @config.page_numbering_mode = @config.page_numbering_mode == :absolute ? :dynamic : :absolute
      @config.save
      set_message("Page numbering: #{@config.page_numbering_mode}")
    end

    def decrease_line_spacing
      clear_selection!
      modes = %i[compact normal relaxed]
      current = modes.index(@config.line_spacing) || 1
      return unless current.positive?

      @config.line_spacing = modes[current - 1]
      @config.save
      @state.last_width = 0
    end

    def calculate_current_pages
      return { current: 0, total: 0 } unless @config.show_page_numbers

      if @config.page_numbering_mode == :dynamic
        return { current: 0, total: 0 } unless @page_manager

        { current: @state.current_page_index + 1, total: @page_manager.total_pages }
      else
        height, width = Terminal.size
        _, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                      @config.view_mode)
        actual_height = adjust_for_line_spacing(content_height)

        return { current: 0, total: 0 } if actual_height <= 0

        update_page_map(width, height) if size_changed?(width, height) || @state.page_map.empty?
        return { current: 0, total: 0 } unless @state.total_pages.positive?

        pages_before = @state.page_map[0...@state.current_chapter].sum
        line_offset = @config.view_mode == :split ? @state.left_page : @state.single_page
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter

        { current: current_global_page, total: @state.total_pages }
      end
    end

    private

    # Hook for subclasses (MouseableReader) to clear any active selection/popup
    def clear_selection!
      # no-op in base controller
    end

    def build_component_layout
      @layout = Components::Layouts::Vertical.new([
                                                    Components::HeaderComponent.new(self),
                                                    Components::ContentComponent.new(self),
                                                    Components::FooterComponent.new(self),
                                                  ])
    end

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      setup_consolidated_reader_bindings
      @dispatcher.activate_stack([:read])
    end

    def setup_consolidated_reader_bindings
      register_reading_bindings_new
      register_help_bindings_new
      register_toc_bindings_new
      register_bookmarks_bindings_new
      register_annotation_editor_bindings_new
      register_annotations_list_bindings_new
      register_popup_bindings_new
    end

    def register_reading_bindings_new
      bindings = {}

      # Navigation using consolidated definitions
      bindings.merge!(Input::CommandFactory.reader_navigation_commands)
      bindings.merge!(Input::CommandFactory.reader_control_commands)

      @dispatcher.register_mode(:read, bindings)
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

    def register_popup_bindings_new
      bindings = {}
      # Route all keys (including ESC) through popup handler so cancel works
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :handle_popup_key }
      bindings[:__default__] = :handle_popup_key
      @dispatcher.register_mode(:popup_menu, bindings)
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
      if @config.page_numbering_mode == :dynamic && @page_manager
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
      Services::LayoutService.adjust_for_line_spacing(height, @config.line_spacing)
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

        old_state = capture_state
        keys.each { |k| @dispatcher.handle_key(k) }
        draw_screen if state_changed?(old_state)
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
      page_value = if @config.page_numbering_mode == :dynamic
                     @state.current_page_index
                   else
                     @config.view_mode == :split ? @state.left_page : @state.single_page
                   end

      { chapter: @state.current_chapter, page: page_value, mode: @state.mode,
        message: @state.message }
    end

    def state_changed?(old_state)
      new_page = if @config.page_numbering_mode == :dynamic
                   @state.current_page_index
                 else
                   @config.view_mode == :split ? @state.left_page : @state.single_page
                 end

      old_state[:chapter] != @state.current_chapter ||
        old_state[:page] != new_page ||
        old_state[:mode] != @state.mode ||
        old_state[:message] != @state.message
    end

    def handle_split_next_page(max_page, content_height)
      if @state.right_page < max_page
        @state.left_page = @state.right_page
        @state.right_page = [@state.right_page + content_height, max_page].min
      else
        @state.left_page = @state.right_page
      end
    end

    def handle_single_next_page(max_page, content_height)
      if @state.single_page < max_page
        @state.single_page = [@state.single_page + content_height, max_page].min
      elsif @state.current_chapter < @doc.chapter_count - 1
        next_chapter
      end
    end

    def handle_split_prev_page(content_height)
      if @state.left_page.positive?
        @state.right_page = @state.left_page
        @state.left_page = [@state.left_page - content_height, 0].max
      elsif @state.current_chapter.positive?
        prev_chapter_with_end_position
      end
    end

    def handle_single_prev_page(content_height)
      if @state.single_page.positive?
        @state.single_page = [@state.single_page - content_height, 0].max
      elsif @state.current_chapter.positive?
        @state.current_chapter -= 1
        position_at_chapter_end
      end
    end

    def prev_chapter_with_end_position
      @state.current_chapter -= 1
      position_at_chapter_end
    end

    def update_page_map(width, height)
      return if @doc.nil?

      # Generate a cache key based on all factors that affect page layout
      cache_key = "#{width}x#{height}-#{@config.view_mode}-#{@config.line_spacing}"

      # Use a cached map if it exists for the current configuration
      if @page_map_cache && @page_map_cache[:key] == cache_key
        @state.page_map = @page_map_cache[:map]
        @state.total_pages = @page_map_cache[:total]
        return
      end

      col_width, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                            @config.view_mode)
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
    end

    def save_progress
      @state_service.save_progress
    end

    def load_bookmarks
      @state.bookmarks = BookmarkManager.get(@path)
    end

    def extract_bookmark_text(chapter, line_offset)
      height, width = Terminal.size
      col_width, = Services::LayoutService.calculate_metrics(width, height, @config.view_mode)
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

      case @config.line_spacing
      when :relaxed
        [height / 2, 1].max
      else # :compact, :normal
        height
      end
    end

    def process_input(key)
      @input_handler.process_input(key)
    end

    def handle_reading_input(key)
      @input_handler.handle_reading_input(key)
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

    public

    # Legacy delegators removed; input handling is centralized via
    # Input::Dispatcher and renderer-driven drawing.

    def jump_to_chapter(chapter_index)
      clear_selection!
      @state.current_chapter = chapter_index
      reset_pages
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
      self.page_offsets = 0
    end

    def position_at_chapter_end
      chapter = @doc.get_chapter(@state.current_chapter)
      return unless chapter&.lines

      col_width, content_height = end_of_chapter_metrics
      return unless content_height.positive?

      wrapped = wrap_lines(chapter.lines, col_width)
      max_page = [wrapped.size - content_height, 0].max
      set_page_end(max_page, content_height)
    end

    def end_of_chapter_metrics
      height, width = Terminal.size
      col_width, content_height = Services::LayoutService.calculate_metrics(width, height,
                                                                            @config.view_mode)
      [col_width, adjust_for_line_spacing(content_height)]
    end

    def set_page_end(max_page, content_height)
      if @config.view_mode == :split
        @state.right_page = max_page
        @state.left_page = [max_page - content_height, 0].max
      else
        @state.single_page = max_page
      end
    end
  end
end
