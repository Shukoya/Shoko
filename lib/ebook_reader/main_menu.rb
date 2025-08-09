# frozen_string_literal: true

require_relative 'ui/main_menu_renderer'
require_relative 'ui/recent_item_renderer'
require_relative 'ui/screens/browse_screen'
require_relative 'ui/screens/menu_screen'
require_relative 'ui/screens/settings_screen'
require_relative 'ui/screens/recent_screen'
require_relative 'ui/screens/open_file_screen'
require_relative 'ui/screens/annotations_screen'
require_relative 'ui/screens/annotation_editor_screen'
require_relative 'services/library_scanner'
require_relative 'concerns/input_handler'
require_relative 'main_menu/screen_manager'
require_relative 'mouseable_reader'
require_relative 'main_menu/actions/file_actions'
require_relative 'main_menu/actions/search_actions'
require_relative 'main_menu/actions/settings_actions'
require_relative 'core/main_menu_state'
require_relative 'input/dispatcher'

module EbookReader
  # Main menu (LazyVim style)
  class MainMenu
    include Concerns::InputHandler
    include Actions::FileActions
    include Actions::SearchActions
    include Actions::SettingsActions

    def initialize
      setup_state
      setup_services
      setup_ui
      @screen_manager = ScreenManager.new(self)
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
      @state = Core::MainMenuState.new
    end

    def setup_services
      @config = Config.new
      @scanner = Services::LibraryScanner.new
      @input_handler = Services::MainMenuInputHandler.new(self)
      setup_input_dispatcher
    end

    def setup_ui
      @renderer = UI::MainMenuRenderer.new(@config)
      @browse_screen = UI::Screens::BrowseScreen.new(@scanner, @renderer)
      @menu_screen = UI::Screens::MenuScreen.new(@renderer, @state.selected)
      @settings_screen = UI::Screens::SettingsScreen.new(@config, @scanner)
      @recent_screen = UI::Screens::RecentScreen.new(self, @renderer)
      @open_file_screen = UI::Screens::OpenFileScreen.new(@renderer)
      @annotations_screen = UI::Screens::AnnotationsScreen.new
      @annotation_editor_screen = UI::Screens::AnnotationEditorScreen.new
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
      keys.each { |k| @dispatcher.handle_key(k) }
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
      @screen_manager.draw_screen
    end

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      register_menu_bindings
      register_browse_bindings
      register_recent_bindings
      register_settings_bindings
      register_open_file_bindings
      register_annotations_bindings
      register_annotation_editor_bindings
      @dispatcher.activate(@state.mode)
    end

    def register_menu_bindings
      b = {}
      ['j', "\e[B", "\eOB"].each { |k| b[k] = ->(ctx, _) { s = ctx.instance_variable_get(:@state); s.selected = (s.selected + 1) % 6; :handled } }
      ['k', "\e[A", "\eOA"].each { |k| b[k] = ->(ctx, _) { s = ctx.instance_variable_get(:@state); s.selected = (s.selected - 1) % 6; :handled } }
      ["\r", "\n"].each { |k| b[k] = ->(ctx, _) { ctx.send(:handle_menu_selection); :handled } }
      b['q'] = ->(ctx, _) { ctx.send(:cleanup_and_exit, 0, ''); :handled }
      b['f'] = ->(ctx, _) { ctx.send(:switch_to_browse); :handled }
      b['r'] = ->(ctx, _) { ctx.send(:switch_to_mode, :recent); :handled }
      b['o'] = ->(ctx, _) { ctx.send(:open_file_dialog); :handled }
      b['s'] = ->(ctx, _) { ctx.send(:switch_to_mode, :settings); :handled }
      @dispatcher.register_mode(:menu, b)
    end

    def register_browse_bindings
      b = {}
      ['j', "\e[B", "\eOB", 'k', "\e[A", "\eOA"].each { |k| b[k] = :navigate_browse }
      ["\r", "\n"].each { |k| b[k] = :open_selected_book }
      b['/'] = ->(ctx, _) { s = ctx.instance_variable_get(:@state); s.search_query = ''; s.search_cursor = 0; :handled }
      b["\e[D"] = ->(ctx, _) { ctx.send(:move_search_cursor, -1); :handled }
      b["\eOD"] = ->(ctx, _) { ctx.send(:move_search_cursor, -1); :handled }
      b["\e[C"] = ->(ctx, _) { ctx.send(:move_search_cursor, 1); :handled }
      b["\eOC"] = ->(ctx, _) { ctx.send(:move_search_cursor, 1); :handled }
      b["\e[3~"] = ->(ctx, _) { ctx.send(:handle_delete); :handled }
      ['\b', "\x7F"].each { |k| b[k] = ->(ctx, _) { ctx.send(:handle_backspace_input); :handled } }
      ["\e", 'q'].each { |k| b[k] = ->(ctx, _) { ctx.send(:switch_to_mode, :menu); :handled } }
      b[:__default__] = ->(ctx, key) do
        ch = key.to_s
        if ch.length == 1 && ch.ord >= 32
          ctx.send(:add_to_search, key)
          :handled
        else
          :pass
        end
      end
      @dispatcher.register_mode(:browse, b)
    end

    def register_recent_bindings
      b = {}
      ["\e", 'q'].each { |k| b[k] = ->(ctx, _) { ctx.send(:switch_to_mode, :menu); :handled } }
      ['j', 'k', "\e[A", "\e[B", "\eOA", "\eOB"].each { |k| b[k] = ->(ctx, key) { ctx.send(:handle_recent_input, key); :handled } }
      ["\r", "\n"].each { |k| b[k] = ->(ctx, key) { ctx.send(:handle_recent_input, key); :handled } }
      @dispatcher.register_mode(:recent, b)
    end

    def register_settings_bindings
      b = {}
      b["\e"] = ->(ctx, _) { ctx.send(:switch_to_mode, :menu); ctx.instance_variable_get(:@config).save; :handled }
      %w[1 2 3 4 5 6].each { |k| b[k] = ->(ctx, key) { ctx.send(:handle_settings_input, key); :handled } }
      @dispatcher.register_mode(:settings, b)
    end

    def register_open_file_bindings
      b = {}
      b["\e"] = ->(ctx, _) { ctx.send(:handle_escape); :handled }
      ["\r", "\n"].each { |k| b[k] = ->(ctx, _) { ctx.send(:handle_enter); :handled } }
      ['\b', "\x7F", "\x08"].each { |k| b[k] = ->(ctx, _) { ctx.send(:handle_backspace_input); :handled } }
      b[:__default__] = ->(ctx, key) { ctx.send(:handle_character_input, key); :handled }
      @dispatcher.register_mode(:open_file, b)
    end

    def register_annotations_bindings
      b = {}
      screen_getter = ->(ctx) { ctx.instance_variable_get(:@annotations_screen) }
      # Exit
      ["\e", 'q'].each { |k| b[k] = ->(ctx, _) { ctx.send(:switch_to_mode, :menu); :handled } }
      # Navigation
      ['j', "\e[B", "\eOB"].each do |k|
        b[k] = ->(ctx, _) do
          screen = screen_getter.call(ctx)
          ctx.instance_variable_get(:@input_handler).send(:navigate_annotations_down, screen)
          :handled
        end
      end
      ['k', "\e[A", "\eOA"].each do |k|
        b[k] = ->(ctx, _) do
          screen = screen_getter.call(ctx)
          ctx.instance_variable_get(:@input_handler).send(:navigate_annotations_up, screen)
          :handled
        end
      end
      # Delete annotation
      b['d'] = ->(ctx, _) do
        screen = screen_getter.call(ctx)
        ctx.instance_variable_get(:@input_handler).send(:delete_annotation, screen)
        :handled
      end
      # Enter to edit selected annotation
      ["\r", "\n"].each do |k|
        b[k] = ->(ctx, _) do
          screen = screen_getter.call(ctx)
          annotation = screen.current_annotation
          book_path = screen.current_book_path
          ctx.send(:switch_to_edit_annotation, annotation, book_path) if annotation && book_path
          :handled
        end
      end
      @dispatcher.register_mode(:annotations, b)
    end

    def register_annotation_editor_bindings
      b = {}
      b[:__default__] = ->(ctx, key) { ctx.instance_variable_get(:@annotation_editor_screen).handle_input(key); :handled }
      @dispatcher.register_mode(:annotation_editor, b)
    end

    def handle_input(key)
      @input_handler.handle_input(key)
    end

    def handle_menu_input(key)
      @input_handler.handle_menu_input(key)
    end

    def switch_to_browse
      @state.mode = :browse
      @state.browse_selected = 0
      @state.search_cursor = @state.search_query.length
      @scanner.start_scan if @scanner.epubs.empty? && @scanner.scan_status == :idle
      @dispatcher.activate(@state.mode)
    end

    def switch_to_mode(mode)
      @state.mode = mode
      @state.browse_selected = 0
      @dispatcher.activate(@state.mode)
    end

    def switch_to_edit_annotation(annotation, book_path)
      editor = instance_variable_get(:@annotation_editor_screen)
      editor.set_annotation(annotation, book_path)
      switch_to_mode(:annotation_editor)
    end

    def handle_menu_selection
      case @state.selected
      when 0 then switch_to_browse
      when 1 then switch_to_mode(:recent)
      when 2 then switch_to_mode(:annotations)
      when 3 then open_file_dialog
      when 4 then switch_to_mode(:settings)
      when 5 then cleanup_and_exit(0, '')
      end
    end

    def handle_browse_input(key)
      @input_handler.handle_browse_input(key)
    end

    def navigate_browse(key)
      return unless @filtered_epubs.any?

      @state.browse_selected = handle_navigation_keys(key, @state.browse_selected, @filtered_epubs.length - 1)
    end

    def refresh_scan
      EPUBFinder.clear_cache
      @scanner.start_scan(force: true)
    end

    def open_selected_book
      return unless @filtered_epubs[@state.browse_selected]

      path = @filtered_epubs[@state.browse_selected]['path']
      if path && File.exist?(path)
        open_book(path)
      else
        @scanner.scan_message = 'File not found'
        @scanner.scan_status = :error
      end
    end

    def searchable_key?(key)
      @input_handler.searchable_key?(key)
    end

    def add_to_search(key)
      @input_handler.send(:add_to_search, key)
    end

    def move_search_cursor(delta)
      @state.search_cursor = (@state.search_cursor + delta).clamp(0, @state.search_query.length)
    end

    def handle_delete
      return if @state.search_cursor >= @state.search_query.length

      query = @state.search_query.dup
      query.slice!(@state.search_cursor)
      @state.search_query = query
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
      path = sanitize_input_path(@state.file_input)
      handle_file_path(path) if path && !path.empty?
      switch_to_mode(:menu)
    end

    def handle_backspace_input
      if @state.file_input.length.positive?
        @state.file_input = @state.file_input[0...-1]
      end
      @open_file_screen.input = @state.file_input
    end

    def handle_character_input(key)
      char = key.to_s
      return unless char.length == 1 && char.ord >= 32

      @state.file_input = (@state.file_input + char)
      @open_file_screen.input = @state.file_input
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
      MouseableReader.new(path, @config).run
    end

    def file_not_found
      @scanner.scan_message = 'File not found'
      @scanner.scan_status = :error
    end

    def handle_reader_error(path, error)
      Infrastructure::Logger.error('Failed to open book', error: error.message, path: path)
      @scanner.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
      @scanner.scan_status = :error
      def filter_by_query
        query = @state.search_query.downcase
        @scanner.epubs.select do |book|
          name = book['name'] || ''
          path = book['path'] || ''
          name.downcase.include?(query) || path.downcase.include?(query)
        end
      end
    end

    def open_file_dialog
      @state.file_input = ''
      @open_file_screen.input = ''
      @state.mode = :open_file
      @dispatcher.activate(@state.mode)
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
      @state.browse_selected = @recent_screen.selected
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
