# frozen_string_literal: true

require_relative 'reader_modes/reading_mode'
require_relative 'reader_modes/help_mode'
require_relative 'reader_modes/toc_mode'
require_relative 'reader_modes/bookmarks_mode'
require_relative 'constants/ui_constants'
require_relative 'errors'
require_relative 'constants/messages'
require_relative 'helpers/reader_helpers'
require_relative 'ui/reader_renderer'
require_relative 'concerns/input_handler'
require_relative 'concerns/bookmarks_ui'
require_relative 'core/reader_state'
require_relative 'services/navigation_service'
require_relative 'services/bookmark_service'
require_relative 'services/state_service'
require_relative 'renderers/components/text_renderer'
require_relative 'dynamic_page_calculator'
require_relative 'reader_display'

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
  class Reader
    include ReaderRefactored::NavigationHelpers
    include ReaderRefactored::DrawingHelpers
    include ReaderRefactored::BookmarkHelpers
    include Constants::UIConstants
    include Helpers::ReaderHelpers
    include Concerns::InputHandler
    include Concerns::BookmarksUI
    include DynamicPageCalculator
    include ReaderDisplay

    attr_accessor :current_chapter, :left_page, :right_page,
                  :single_page, :current_page_index
    attr_reader :doc, :config, :page_manager, :path

    def initialize(epub_path, config = Config.new)
      @path = epub_path
      @config = config
      @renderer = UI::ReaderRenderer.new(@config)
      initialize_state
      load_document
      @page_manager = Services::PageManager.new(@doc, @config) if @doc
      @navigation_service = Services::NavigationService.new(self)
      @bookmark_service = Services::BookmarkService.new(self)
      @state_service = Services::StateService.new(self)
      load_data
      @input_handler = Services::ReaderInputHandler.new(self)
      @terminal_cache = { width: nil, height: nil, checked_at: nil }
      @last_rendered_content = {}
      @wrap_cache = {}
    end

    def run
      Terminal.setup
      main_loop
    ensure
      Terminal.cleanup
    end

    def switch_mode(mode)
      @mode = mode
    end

    def scroll_down
      return if @config.page_numbering_mode == :dynamic

      if @config.view_mode == :split
        @left_page = [@left_page + 1, @max_page || 0].min
        @right_page = [@right_page + 1, @max_page || 0].min
      else
        @single_page = [@single_page + 1, @max_page || 0].min
      end
    end

    def scroll_up
      return if @config.page_numbering_mode == :dynamic

      if @config.view_mode == :split
        @left_page = [@left_page - 1, 0].max
        @right_page = [@right_page - 1, 0].max
      else
        @single_page = [@single_page - 1, 0].max
      end
    end

    def next_page
      if @config.page_numbering_mode == :dynamic
        next_page_dynamic
      else
        next_page_absolute
      end
    end

    def prev_page
      if @config.page_numbering_mode == :dynamic
        prev_page_dynamic
      else
        prev_page_absolute
      end
    end

    def next_page_dynamic
      return unless @page_manager

      return unless @current_page_index < @page_manager.total_pages - 1

      @current_page_index += 1
      update_chapter_from_page_index
    end

    def prev_page_dynamic
      return unless @page_manager

      return unless @current_page_index.positive?

      @current_page_index -= 1
      update_chapter_from_page_index
    end

    def next_page_absolute
      @navigation_service.next_page_absolute
    end

    def prev_page_absolute
      return if @current_chapter.zero? && @single_page.zero? && @left_page.zero?

      height, width = Terminal.size
      _, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)

      if @config.view_mode == :split
        handle_split_prev_page(content_height)
      else
        handle_single_prev_page(content_height)
      end
    end

    def update_chapter_from_page_index
      page_data = @page_manager.get_page(@current_page_index)
      return unless page_data

      @current_chapter = page_data[:chapter_index]
    end

    def go_to_start
      reset_pages
    end

    def go_to_end
      @navigation_service.go_to_end
    end

    def quit_to_menu
      save_progress
      @running = false
    end

    def quit_application
      save_progress
      Terminal.cleanup
      exit 0
    end

    def next_chapter
      @navigation_service.next_chapter
    end

    def prev_chapter
      @navigation_service.prev_chapter
    end

    def add_bookmark
      @bookmark_service.add_bookmark
    end

    def toggle_view_mode
      @config.view_mode = @config.view_mode == :split ? :single : :split
      @config.save
      @last_width = 0
      @last_height = 0
      @dynamic_page_map = nil
      @dynamic_total_pages = 0
      @last_dynamic_width = 0
      @last_dynamic_height = 0
      reset_pages
    end

    def increase_line_spacing
      modes = %i[compact normal relaxed]
      current = modes.index(@config.line_spacing) || 1
      return unless current < 2

      @config.line_spacing = modes[current + 1]
      @config.save
      @last_width = 0
    end

    def toggle_page_numbering_mode
      @config.page_numbering_mode = @config.page_numbering_mode == :absolute ? :dynamic : :absolute
      @config.save
      set_message("Page numbering: #{@config.page_numbering_mode}")
    end

    def decrease_line_spacing
      modes = %i[compact normal relaxed]
      current = modes.index(@config.line_spacing) || 1
      return unless current.positive?

      @config.line_spacing = modes[current - 1]
      @config.save
      @last_width = 0
    end

    ERROR_MESSAGE_LINES = [
      'Failed to load EPUB file:',
      '',
      '%<error>s',
      '',
      'Possible causes:',
      '- The file might be corrupted',
      '- The file might not be a valid EPUB',
      '- The file might be password protected',
      '',
      "Press 'q' to return to the menu",
    ].freeze
    private_constant :ERROR_MESSAGE_LINES

    private

    def initialize_state
      @current_chapter = @left_page = @right_page = @single_page = @current_page_index = 0
      @running = true
      @mode = :read
      @toc_selected = 0
      @bookmarks = []
      @bookmark_selected = 0
      @message = nil
      @page_map = []
      @total_pages = 0
      @last_width = @last_height = 0
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
      while @running
        keys = read_input_keys
        next if keys.empty?

        old_state = capture_state
        keys.each { |k| @input_handler.process_input(k) }
        draw_screen if state_changed?(old_state)
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
                     @current_page_index
                   else
                     @config.view_mode == :split ? @left_page : @single_page
                   end

      { chapter: @current_chapter, page: page_value, mode: @mode, message: @message }
    end

    def state_changed?(old_state)
      new_page = if @config.page_numbering_mode == :dynamic
                   @current_page_index
                 else
                   @config.view_mode == :split ? @left_page : @single_page
                 end

      old_state[:chapter] != @current_chapter ||
        old_state[:page] != new_page ||
        old_state[:mode] != @mode ||
        old_state[:message] != @message
    end

    def handle_split_next_page(max_page, content_height)
      if @right_page < max_page
        @left_page = @right_page
        @right_page = [@right_page + content_height, max_page].min
      else
        @left_page = @right_page
      end
    end

    def handle_single_next_page(max_page, content_height)
      if @single_page < max_page
        @single_page = [@single_page + content_height, max_page].min
      elsif @current_chapter < @doc.chapter_count - 1
        next_chapter
      end
    end

    def handle_split_prev_page(content_height)
      if @left_page.positive?
        @right_page = @left_page
        @left_page = [@left_page - content_height, 0].max
      elsif @current_chapter.positive?
        prev_chapter_with_end_position
      end
    end

    def handle_single_prev_page(content_height)
      if @single_page.positive?
        @single_page = [@single_page - content_height, 0].max
      elsif @current_chapter.positive?
        @current_chapter -= 1
        position_at_chapter_end
      end
    end

    def prev_chapter_with_end_position
      @current_chapter -= 1
      position_at_chapter_end
    end

    def update_page_map(width, height)
      return if @doc.nil?

      col_width, content_height = get_layout_metrics(width, height)
      actual_height = adjust_for_line_spacing(content_height)
      return if actual_height <= 0

      calculate_page_map(col_width, actual_height)
      @last_width = width
      @last_height = height
    end

    def calculate_page_map(col_width, actual_height)
      @page_map = @doc.chapters.map do |chapter|
        wrapped = wrap_lines(chapter.lines || [], col_width)
        (wrapped.size.to_f / actual_height).ceil
      end
      @total_pages = @page_map.sum
    end

    def get_layout_metrics(width, height)
      col_width = if @config.view_mode == :split
                    [(width - 3) / 2, MIN_COLUMN_WIDTH].max
                  else
                    (width * 0.9).to_i.clamp(30, 120)
                  end
      content_height = [height - 2, 1].max
      [col_width, content_height]
    end

    def load_progress
      @state_service.load_progress
    end

    def page_offsets=(offset)
      @single_page = offset
      @left_page = offset
      @right_page = offset
    end

    def save_progress
      @state_service.save_progress
    end

    def load_bookmarks
      @bookmarks = BookmarkManager.get(@path)
    end

    def extract_bookmark_text(chapter, line_offset)
      height, width = Terminal.size
      col_width, = get_layout_metrics(width, height)
      wrapped = wrap_lines(chapter.lines || [], col_width)
      text = wrapped[line_offset] || 'Bookmark'
      text.strip[0, 50]
    end

    def set_message(text, duration = 2)
      @message = text
      Thread.new do
        sleep duration
        @message = nil
      end
    end

    def create_error_document(error_msg)
      doc = Object.new
      define_error_doc_methods(doc, error_msg)
      doc
    end

    def define_error_doc_methods(doc, error_msg)
      doc.define_singleton_method(:title) { 'Error Loading EPUB' }
      doc.define_singleton_method(:language) { 'en_US' }
      doc.define_singleton_method(:chapter_count) { 1 }
      doc.define_singleton_method(:chapters) { [{ title: 'Error', lines: [] }] }
      doc.define_singleton_method(:get_chapter) do |_idx|
        { number: '1', title: 'Error', lines: error_lines(error_msg) }
      end
    end

    def error_lines(error_msg)
      ERROR_MESSAGE_LINES.map { |line| line == '%<error>s' ? error_msg : line }
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
      @mode = :toc
      @toc_selected = @current_chapter
    end

    def open_bookmarks
      @mode = :bookmarks
      @bookmark_selected = 0
    end

    def handle_navigation_input(key)
      @input_handler.handle_navigation_input(key)
    end

    def navigate_by_key(key, content_height, max_page)
      @input_handler.navigate_by_key(key, content_height, max_page)
    end

    def scroll_down_with_max(max_page)
      @input_handler.scroll_down_with_max(max_page)
    end

    def next_page_with_params(content_height, max_page)
      @input_handler.next_page_with_params(content_height, max_page)
    end

    def prev_page_with_params(content_height)
      @input_handler.prev_page_with_params(content_height)
    end

    def go_to_end_with_params(content_height, max_page)
      @input_handler.go_to_end_with_params(content_height, max_page)
    end

    def handle_next_chapter
      @input_handler.handle_next_chapter
    end

    def handle_prev_chapter
      @input_handler.handle_prev_chapter
    end

    def handle_toc_input(key)
      @input_handler.handle_toc_input(key)
    end

    def jump_to_chapter(chapter_index)
      @current_chapter = chapter_index
      reset_pages
      save_progress
      @mode = :read
    end

    def handle_bookmarks_input(key)
      @input_handler.handle_bookmarks_input(key)
    end

    def handle_empty_bookmarks_input(key)
      @input_handler.handle_empty_bookmarks_input(key)
    end

    def jump_to_bookmark
      bookmark = @bookmarks[@bookmark_selected]
      return unless bookmark

      @current_chapter = bookmark.chapter_index
      self.page_offsets = bookmark.line_offset
      save_progress
      @mode = :read
    end

    def delete_selected_bookmark
      bookmark = @bookmarks[@bookmark_selected]
      return unless bookmark

      BookmarkManager.delete(@path, bookmark)
      load_bookmarks
      @bookmark_selected = [@bookmark_selected, @bookmarks.length - 1].min if @bookmarks.any?
      set_message(Constants::Messages::BOOKMARK_DELETED)
    end

    def reset_pages
      self.page_offsets = 0
    end

    def position_at_chapter_end
      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter&.lines

      col_width, content_height = end_of_chapter_metrics
      return unless content_height.positive?

      wrapped = wrap_lines(chapter.lines, col_width)
      max_page = [wrapped.size - content_height, 0].max
      set_page_end(max_page, content_height)
    end

    def end_of_chapter_metrics
      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      [col_width, adjust_for_line_spacing(content_height)]
    end

    def set_page_end(max_page, content_height)
      if @config.view_mode == :split
        @right_page = max_page
        @left_page = [max_page - content_height, 0].max
      else
        @single_page = max_page
      end
    end
  end
end
