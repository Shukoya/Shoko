# frozen_string_literal: true

require_relative 'ui/main_menu_renderer'
require_relative 'ui/recent_item_renderer'
require_relative 'ui/screens/browse_screen'
require_relative 'ui/screens/menu_screen'
require_relative 'ui/screens/settings_screen'
require_relative 'ui/screens/recent_screen'
require_relative 'ui/screens/open_file_screen'
require_relative 'services/library_scanner'
require_relative 'concerns/input_handler'

module EbookReader
  # Main menu (LazyVim style)
  class MainMenu
    include Concerns::InputHandler

    def initialize
      setup_state
      setup_services
      setup_ui
    end

    def run
      Terminal.setup
      @scanner.load_cached
      @scanner.start_scan if @scanner.epubs.empty?

      main_loop
    rescue Interrupt
      cleanup_and_exit(0, "\nGoodbye!")
    rescue StandardError => e
      cleanup_and_exit(1, "Error: #{e.message}", e)
    ensure
      @scanner.cleanup
    end

    private

    def setup_state
      @selected = 0
      @mode = :menu
      @browse_selected = 0
      @search_query = ''
      @search_cursor = 0
      @file_input = ''
    end

    def setup_services
      @config = Config.new
      @scanner = Services::LibraryScanner.new
      @input_handler = Services::MainMenuInputHandler.new(self)
    end

    def setup_ui
      @renderer = UI::MainMenuRenderer.new(@config)
      @browse_screen = UI::Screens::BrowseScreen.new(@scanner)
      @menu_screen = UI::Screens::MenuScreen.new(@renderer, @selected)
      @settings_screen = UI::Screens::SettingsScreen.new(@config, @scanner)
      @recent_screen = UI::Screens::RecentScreen.new(self)
      @open_file_screen = UI::Screens::OpenFileScreen.new
    end

    def main_loop
      draw_screen
      loop do
        process_scan_results_if_available
        handle_user_input
        draw_screen
      end
    end

    def handle_user_input
      keys = read_input_keys
      keys.each { |k| @input_handler.handle_input(k) }
    end

    def read_input_keys
      key = Terminal.read_key_blocking
      keys = [key]
      collect_additional_keys(keys)
      keys
    end

    def collect_additional_keys(keys)
      while (extra = Terminal.read_key)
        keys << extra
        break if keys.size > 10
      end
    end

    def process_scan_results_if_available
      return unless (epubs = @scanner.process_results)

      @scanner.epubs = epubs
      filter_books
    end

    def cleanup_and_exit(code, message, error = nil)
      Terminal.cleanup
      puts message
      puts error.backtrace if error && EPUBFinder::DEBUG_MODE
      exit code
    end

    def draw_screen
      Terminal.start_frame
      height, width = Terminal.size

      case @mode
      when :menu then draw_main_menu(height, width)
      when :browse then draw_browse_screen(height, width)
      when :recent then draw_recent_screen(height, width)
      when :settings then draw_settings_screen(height, width)
      when :open_file then draw_open_file_screen(height, width)
      end

      Terminal.end_frame
    end

    def draw_main_menu(height, width)
      @menu_screen.selected = @selected
      @menu_screen.draw(height, width)
    end

    def draw_browse_screen(height, width)
      @browse_screen.selected = @browse_selected
      @browse_screen.search_query = @search_query
      @browse_screen.search_cursor = @search_cursor
      @browse_screen.filtered_epubs = @filtered_epubs
      @browse_screen.draw(height, width)
    end

    def draw_recent_screen(height, width)
      @recent_screen.selected = @browse_selected
      @recent_screen.draw(height, width)
    end

    def draw_settings_screen(height, width)
      @settings_screen.draw(height, width)
    end

    def draw_open_file_screen(height, width)
      @open_file_screen.draw(height, width)
    end

    def handle_input(key)
      @input_handler.handle_input(key)
    end

    def handle_menu_input(key)
      @input_handler.handle_menu_input(key)
    end

    def switch_to_browse
      @mode = :browse
      @browse_selected = 0
      @search_cursor = @search_query.length
      @scanner.start_scan if @scanner.epubs.empty? && @scanner.scan_status == :idle
    end

    def switch_to_mode(mode)
      @mode = mode
      @browse_selected = 0
    end

    def handle_menu_selection
      case @selected
      when 0 then switch_to_browse
      when 1 then switch_to_mode(:recent)
      when 2 then open_file_dialog
      when 3 then switch_to_mode(:settings)
      when 4 then cleanup_and_exit(0, '')
      end
    end

    def handle_browse_input(key)
      @input_handler.handle_browse_input(key)
    end

    def navigate_browse(key)
      return unless @filtered_epubs.any?

      @browse_selected = handle_navigation_keys(key, @browse_selected, @filtered_epubs.length - 1)
    end

    def refresh_scan
      EPUBFinder.clear_cache
      @scanner.start_scan(force: true)
    end

    def open_selected_book
      return unless @filtered_epubs[@browse_selected]

      path = @filtered_epubs[@browse_selected]['path']
      if path && File.exist?(path)
        open_book(path)
      else
        @scanner.scan_message = 'File not found'
        @scanner.scan_status = :error
      end
    end

    def handle_backspace
      @input_handler.send(:handle_backspace)
    end

    def searchable_key?(key)
      @input_handler.searchable_key?(key)
    end

    def add_to_search(key)
      @input_handler.send(:add_to_search, key)
    end

    def move_search_cursor(delta)
      @search_cursor = (@search_cursor + delta).clamp(0, @search_query.length)
    end

    def handle_delete
      return if @search_cursor >= @search_query.length

      query = @search_query.dup
      query.slice!(@search_cursor)
      @search_query = query
      filter_books
    end

    def handle_recent_input(key)
      @input_handler.handle_recent_input(key)
    end

    def handle_settings_input(key)
      @input_handler.handle_settings_input(key)
    end

    def handle_open_file_input(key)
      return unless key

      case key
      when "\e" then handle_escape
      when "\r", "\n" then handle_enter
      when *backspace_keys then handle_backspace_input
      else handle_character_input(key)
      end
    end

    def backspace_keys
      ["\b", "\x7F", "\x08"]
    end

    def handle_escape
      switch_to_mode(:menu)
    end

    def handle_enter
      path = sanitize_input_path(@file_input)
      handle_file_path(path) if path && !path.empty?
      switch_to_mode(:menu)
    end

    def handle_backspace_input
      @file_input = @file_input[0...-1] if @file_input.length.positive?
      @open_file_screen.input = @file_input
    end

    def handle_character_input(key)
      char = key.to_s
      return unless char.length == 1 && char.ord >= 32

      @file_input += char
      @open_file_screen.input = @file_input
    end

    def handle_setting_change(key)
      @input_handler.handle_setting_change(key)
    end

    def toggle_view_mode
      @config.view_mode = @config.view_mode == :split ? :single : :split
      @config.save
    end

    def toggle_page_numbers
      @config.show_page_numbers = !@config.show_page_numbers
      @config.save
    end

    def cycle_line_spacing
      modes = %i[compact normal relaxed]
      current = modes.index(@config.line_spacing) || 1
      @config.line_spacing = modes[(current + 1) % 3]
      @config.save
    end

    def toggle_highlight_quotes
      @config.highlight_quotes = !@config.highlight_quotes
      @config.save
    end

    def toggle_page_numbering_mode
      @config.page_numbering_mode = @config.page_numbering_mode == :absolute ? :dynamic : :absolute
      @config.save
    end

    def clear_cache
      EPUBFinder.clear_cache
      @scanner.epubs = []
      @filtered_epubs = []
      @scanner.scan_status = :idle
      @scanner.scan_message = "Cache cleared! Use 'Find Book' to rescan"
    end

    def filter_books
      @filtered_epubs = if @search_query.empty?
                          @scanner.epubs
                        else
                          filter_by_query
                        end
      @browse_selected = 0
    end

    def filter_by_query
      query = @search_query.downcase
      @scanner.epubs.select do |book|
        name = book['name'] || ''
        path = book['path'] || ''
        name.downcase.include?(query) || path.downcase.include?(query)
      end
    end

    def open_book(path)
      return file_not_found unless File.exist?(path)

      run_reader(path)
    rescue StandardError => e
      handle_reader_error(path, e)
    ensure
      Terminal.setup
    end

    def run_reader(path)
      Terminal.cleanup
      RecentFiles.add(path)
      Reader.new(path, @config).run
    end

    def file_not_found
      @scanner.scan_message = 'File not found'
      @scanner.scan_status = :error
    end

    def handle_reader_error(path, error)
      Infrastructure::Logger.error('Failed to open book', error: error.message, path: path)
      @scanner.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
      @scanner.scan_status = :error
      puts error.backtrace.join("\n") if EPUBFinder::DEBUG_MODE
    end

    def open_file_dialog
      @file_input = ''
      @open_file_screen.input = ''
      @mode = :open_file
    end

    def sanitize_input_path(input)
      return '' unless input

      path = input.chomp.strip
      if (path.start_with?("'") && path.end_with?("'")) ||
         (path.start_with?('"') && path.end_with?('"'))
        path = path[1..-2]
      end
      path = path.delete('"')
      File.expand_path(path)
    end

    def handle_file_path(path)
      if File.exist?(path) && path.downcase.end_with?('.epub')
        RecentFiles.add(path)
        reader = Reader.new(path, @config)
        reader.run
      else
        @scanner.scan_message = 'Invalid file path'
        @scanner.scan_status = :error
      end
    end

    def load_recent_books
      books = @recent_screen.send(:load_recent_books)
      @browse_selected = @recent_screen.selected
      books
    end

    def handle_dialog_error(error)
      puts "Error: #{error.message}"
      sleep 2
      Terminal.setup
    end

    def time_ago_in_words(time)
      return 'unknown' unless time

      seconds = Time.now - time
      format_time_ago(seconds, time)
    rescue StandardError
      'unknown'
    end

    def format_time_ago(seconds, time)
      case seconds
      when 0..59 then 'just now'
      when 60..3599 then "#{(seconds / 60).to_i}m ago"
      when 3600..86_399 then "#{(seconds / 3600).to_i}h ago"
      when 86_400..604_799 then "#{(seconds / 86_400).to_i}d ago"
      else time.strftime('%b %d')
      end
    end
  end
end
