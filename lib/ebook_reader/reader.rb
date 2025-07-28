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
require_relative 'services/reader_navigation'
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

    attr_reader :current_chapter, :doc, :config

    def initialize(epub_path, config = Config.new)
      @path = epub_path
      @config = config
      @renderer = UI::ReaderRenderer.new(@config)
      initialize_state
      load_document
      load_data
      @input_handler = Services::ReaderInputHandler.new(self)
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
      if @config.view_mode == :split
        @left_page = [@left_page + 1, @max_page || 0].min
        @right_page = [@right_page + 1, @max_page || 0].min
      else
        @single_page = [@single_page + 1, @max_page || 0].min
      end
    end

    def scroll_up
      if @config.view_mode == :split
        @left_page = [@left_page - 1, 0].max
        @right_page = [@right_page - 1, 0].max
      else
        @single_page = [@single_page - 1, 0].max
      end
    end

    def next_page
      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)

      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      wrapped = wrap_lines(chapter.lines || [], col_width)
      max_page = [wrapped.size - content_height, 0].max

      if @config.view_mode == :split
        handle_split_next_page(max_page, content_height)
      else
        handle_single_next_page(max_page, content_height)
      end
    end

    def prev_page
      height, width = Terminal.size
      _, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)

      if @config.view_mode == :split
        handle_split_prev_page(content_height)
      else
        handle_single_prev_page(content_height)
      end
    end

    def go_to_start
      reset_pages
    end

    def go_to_end
      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)

      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      wrapped = wrap_lines(chapter.lines || [], col_width)
      max_page = [wrapped.size - content_height, 0].max

      if @config.view_mode == :split
        @right_page = max_page
        @left_page = [max_page - content_height, 0].max
      else
        @single_page = max_page
      end
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
      @current_chapter += 1
      reset_pages
      save_progress
    end

    def prev_chapter
      @current_chapter -= 1
      reset_pages
    end

    def add_bookmark
      line_offset = @config.view_mode == :split ? @left_page : @single_page
      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      text_snippet = extract_bookmark_text(chapter, line_offset)
      BookmarkManager.add(@path, @current_chapter, line_offset, text_snippet)
      load_bookmarks
      set_message(Constants::Messages::BOOKMARK_ADDED)
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

    # Enter a temporary copy mode where the current page can be highlighted
    # without leaving the reader interface.
    def enter_copy_mode
      @copy_mode = true
      draw_screen
      Terminal.read_key_blocking
    ensure
      @copy_mode = false
      draw_screen
    end

    # Collect the lines currently visible on screen and print them without
    # terminal escape codes.
    def print_copy_text
      lines = current_page_lines
      puts lines.join("\n")
      puts
      puts '[Press any key to return]'
    end

    # Determine the text for the current visible page respecting view mode.
    def current_page_lines
      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      actual_height = adjust_for_line_spacing(content_height)

      chapter = @doc.get_chapter(@current_chapter)
      return [] unless chapter

      wrapped = wrap_lines(chapter.lines || [], col_width)

      if @config.view_mode == :split
        left_lines  = calculate_visible_lines(wrapped, @left_page, actual_height)
        right_lines = calculate_visible_lines(wrapped, @right_page, actual_height)
        max_lines = [left_lines.length, right_lines.length].max
        Array.new(max_lines) do |i|
          format("%-#{col_width}s    %s", left_lines[i].to_s, right_lines[i].to_s)
        end
      else
        calculate_visible_lines(wrapped, @single_page, actual_height)
      end
    end

    private

    def initialize_state
      @current_chapter = 0
      @left_page = 0
      @right_page = 0
      @single_page = 0
      @running = true
      @mode = :read
      @toc_selected = 0
      @bookmarks = []
      @bookmark_selected = 0
      @message = nil
      @page_map = []
      @total_pages = 0
      @last_width = 0
      @last_height = 0
      @copy_mode = false
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
      while @running
        draw_screen
        key = Terminal.read_key
        @input_handler.process_input(key) if key
        sleep KEY_REPEAT_DELAY / 1000.0
      end
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
        prev_chapter_with_end_position
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
      progress = ProgressManager.load(@path)
      return unless progress

      @current_chapter = progress['chapter'] || 0
      line_offset = progress['line_offset'] || 0

      @current_chapter = 0 if @current_chapter >= @doc.chapter_count

      self.page_offsets = line_offset
    end

    def page_offsets=(offset)
      @single_page = offset
      @left_page = offset
      @right_page = offset
    end

    def save_progress
      return unless @path && @doc

      line_offset = @config.view_mode == :split ? @left_page : @single_page
      ProgressManager.save(@path, @current_chapter, line_offset)
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
      doc.define_singleton_method(:title) { 'Error Loading EPUB' }
      doc.define_singleton_method(:language) { 'en_US' }
      doc.define_singleton_method(:chapter_count) { 1 }
      doc.define_singleton_method(:chapters) { [{ title: 'Error', lines: [] }] }
      doc.define_singleton_method(:get_chapter) do |_idx|
        {
          number: '1',
          title: 'Error',
          lines: build_error_lines(error_msg),
        }
      end
      doc
    end

    def build_error_lines(error_msg)
      [
        'Failed to load EPUB file:',
        '',
        error_msg,
        '',
        'Possible causes:',
        '- The file might be corrupted',
        '- The file might not be a valid EPUB',
        '- The file might be password protected',
        '',
        "Press 'q' to return to the menu",
      ]
    end

    def adjust_for_line_spacing(height)
      return 1 if height <= 0

      return height unless @config.line_spacing == :relaxed

      [height / 2, 1].max
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

      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)
      wrapped = wrap_lines(chapter.lines, col_width)
      max_page = [wrapped.size - content_height, 0].max

      if @config.view_mode == :split
        @right_page = max_page
        @left_page = [max_page - content_height, 0].max
      else
        @single_page = max_page
      end
    end
  end
end
