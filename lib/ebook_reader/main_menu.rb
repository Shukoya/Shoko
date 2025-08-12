# frozen_string_literal: true

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
    include Input::KeyDefinitions::Helpers

    attr_reader :state, :config, :annotations_screen, :input_handler

    def initialize
      setup_state
      setup_services
      setup_ui
      @screen_manager = ScreenManager.new(self)
    end

    def run
      Terminal.setup
      @scanner.load_cached
      @filtered_epubs = @scanner.epubs || []
      @browse_screen.filtered_epubs = @filtered_epubs
      @scanner.start_scan if @scanner.epubs.empty?

      main_loop
    rescue Interrupt
      cleanup_and_exit(0, "\nGoodbye!")
    rescue StandardError => e
      cleanup_and_exit(1, "Error: #{e.message}", e)
    ensure
      @scanner.cleanup
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

    def handle_navigation(direction)
      current = @state.selected
      max_val = 5 # 6 menu items (0-5)

      @state.selected = case direction
                        when :up then [current - 1, 0].max
                        when :down then [current + 1, max_val].min
                        else current
                        end
    end

    def switch_to_browse
      @state.mode = :browse
      @state.search_active = false
      @browse_screen.search_active = false
      @dispatcher.activate(@state.mode)
    end

    def switch_to_search
      @state.mode = :search
      @state.search_active = true
      @browse_screen.search_active = true
      @dispatcher.activate(@state.mode)
    end

    def switch_to_mode(mode)
      @state.mode = mode
      @state.browse_selected = 0
      @dispatcher.activate(@state.mode)
    end

    def open_file_dialog
      @state.file_input = ''
      @open_file_screen.input = ''
      @state.mode = :open_file
      @dispatcher.activate(@state.mode)
    end

    def cleanup_and_exit(code, message, error = nil)
      Terminal.cleanup
      puts message
      puts error.backtrace if error && EPUBFinder::DEBUG_MODE
      exit code
    end

    def handle_browse_navigation(key)
      @browse_screen.navigate(key)
      @state.browse_selected = @browse_screen.selected
    end

    def handle_recent_input(key)
      @input_handler.handle_recent_input(key)
    end

    def handle_backspace_input
      if @state.search_active
        if @state.search_query.length.positive?
          @state.search_query = @state.search_query[0...-1]
          filter_browse_screen
        end
      elsif @state.file_input.length.positive?
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

    def switch_to_edit_annotation(annotation, book_path)
      editor = instance_variable_get(:@annotation_editor_screen)
      editor.set_annotation(annotation, book_path)
      switch_to_mode(:annotation_editor)
    end

    def refresh_scan
      @scanner.start_scan(force: true)
    end

    # Methods expected by BindingGenerator - MUST be public
    def handle_selection
      handle_menu_selection
    end
    
    def handle_cancel
      case @state.mode
      when :menu
        cleanup_and_exit(0, '')
      when :browse, :recent, :settings, :annotations, :annotation_editor, :open_file
        switch_to_mode(:menu)
      else
        switch_to_mode(:menu)
      end
    end
    
    def exit_current_mode
      handle_cancel
    end
    
    def delete_selected_item
      # This would be context-dependent, but for now just pass
      case @state.mode
      when :browse
        handle_delete if respond_to?(:handle_delete)
      else
        # No-op for other modes
      end
    end
    
    def handle_settings_input(key)
      @input_handler.handle_setting_change(key)
    end

    private

    def setup_state
      @state = Core::MainMenuState.new
      @filtered_epubs = []
    end

    def setup_services
      @config = Config.new
      @scanner = Services::LibraryScanner.new
      @input_handler = Services::MainMenuInputHandler.new(self)
      setup_input_dispatcher
    end

    def setup_ui
      @renderer = nil
      @browse_screen = UI::Screens::BrowseScreen.new(@scanner)
      @menu_screen = UI::Screens::MenuScreen.new(nil, @state.selected)
      @settings_screen = UI::Screens::SettingsScreen.new(@config, @scanner)
      @recent_screen = UI::Screens::RecentScreen.new(self)
      @open_file_screen = UI::Screens::OpenFileScreen.new(nil)
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
      @filtered_epubs = @scanner.epubs
      @browse_screen.filtered_epubs = @scanner.epubs
    end

    def navigate_browse(key)
      handle_browse_navigation(key)
    end

    def draw_screen
      @screen_manager.draw_screen
    end

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      setup_consolidated_input_bindings
      @dispatcher.activate(@state.mode)
    end

    def setup_consolidated_input_bindings
      register_menu_bindings
      register_browse_bindings
      register_search_bindings
      register_recent_bindings
      register_settings_bindings
      register_open_file_bindings
      register_annotations_bindings
      register_annotation_editor_bindings
    end

    def register_menu_bindings
      custom_methods = {
        up: lambda { |ctx, _|
          ctx.handle_navigation(:up)
          :handled
        },
        down: lambda { |ctx, _|
          ctx.handle_navigation(:down)
          :handled
        },
        confirm: lambda { |ctx, _|
          ctx.handle_menu_selection
          :handled
        },
        browse: lambda { |ctx, _|
          ctx.switch_to_browse
          :handled
        },
        recent: lambda { |ctx, _|
          ctx.switch_to_mode(:recent)
          :handled
        },
        open_file: lambda { |ctx, _|
          ctx.open_file_dialog
          :handled
        },
        settings: lambda { |ctx, _|
          ctx.switch_to_mode(:settings)
          :handled
        },
        annotations: lambda { |ctx, _|
          ctx.switch_to_mode(:annotations)
          :handled
        },
        quit: lambda { |ctx, _|
          ctx.cleanup_and_exit(0, '')
          :handled
        },
        cancel: lambda { |ctx, _|
          ctx.cleanup_and_exit(0, '')
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:menu, custom_methods)
      @dispatcher.register_mode(:menu, bindings)
    end

    def register_browse_bindings
      custom_methods = {
        up: lambda { |ctx, k|
          ctx.handle_browse_navigation(k)
          :handled
        },
        down: lambda { |ctx, k|
          ctx.handle_browse_navigation(k)
          :handled
        },
        confirm: :open_selected_book,
        cancel: lambda { |ctx, _|
          ctx.switch_to_mode(:menu)
          :handled
        },
        quit: lambda { |ctx, _|
          ctx.switch_to_mode(:menu)
          :handled
        },
        search: lambda { |ctx, _|
          ctx.switch_to_search
          :handled
        },
        refresh: lambda { |ctx, _|
          ctx.refresh_scan
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:browse, custom_methods)
      @dispatcher.register_mode(:browse, bindings)
    end

    def register_search_bindings
      custom_methods = {
        confirm: lambda { |ctx, _|
          ctx.switch_to_browse
          :handled
        },
        cancel: lambda { |ctx, _|
          ctx.switch_to_browse
          :handled
        },
        left: lambda { |ctx, _|
          ctx.move_search_cursor(-1)
          :handled
        },
        right: lambda { |ctx, _|
          ctx.move_search_cursor(1)
          :handled
        },
        delete: lambda { |ctx, _|
          ctx.handle_delete
          :handled
        },
        backspace: lambda { |ctx, _|
          ctx.handle_backspace_input
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:search, custom_methods)
      # Add text input handler
      bindings[:__default__] = lambda { |ctx, key|
        char = key.to_s
        if char.length == 1 && char.ord >= 32
          (ctx.add_to_search(key)
           :handled)
        else
          :pass
        end
      }

      @dispatcher.register_mode(:search, bindings)
    end

    def register_recent_bindings
      custom_methods = {
        cancel: lambda { |ctx, _|
          ctx.switch_to_mode(:menu)
          :handled
        },
        up: lambda { |ctx, k|
          ctx.handle_recent_input(k)
          :handled
        },
        down: lambda { |ctx, k|
          ctx.handle_recent_input(k)
          :handled
        },
        confirm: lambda { |ctx, k|
          ctx.handle_recent_input(k)
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:recent, custom_methods)
      @dispatcher.register_mode(:recent, bindings)
    end

    def register_settings_bindings
      custom_methods = {
        cancel: lambda { |ctx, _|
          ctx.switch_to_mode(:menu)
          ctx.config.save
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:settings, custom_methods)
      # Add number key handlers
      %w[1 2 3 4 5 6].each do |k|
        bindings[k] = lambda { |ctx, key|
          ctx.handle_settings_input(key)
          :handled
        }
      end

      @dispatcher.register_mode(:settings, bindings)
    end

    def register_open_file_bindings
      custom_methods = {
        cancel: lambda { |ctx, _|
          ctx.handle_escape
          :handled
        },
        confirm: lambda { |ctx, _|
          ctx.handle_enter
          :handled
        },
        backspace: lambda { |ctx, _|
          ctx.handle_backspace_input
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:open_file, custom_methods)
      bindings[:__default__] = lambda { |ctx, key|
        ctx.handle_character_input(key)
        :handled
      }

      @dispatcher.register_mode(:open_file, bindings)
    end

    def register_annotations_bindings
      custom_methods = {
        cancel: lambda { |ctx, _|
          ctx.switch_to_mode(:menu)
          :handled
        },
        up: lambda { |ctx, _|
          ctx.input_handler.navigate_annotations_up(ctx.annotations_screen)
          :handled
        },
        down: lambda { |ctx, _|
          ctx.input_handler.navigate_annotations_down(ctx.annotations_screen)
          :handled
        },
        confirm: lambda { |ctx, _|
          screen = ctx.annotations_screen
          annotation = screen.current_annotation
          book_path = screen.current_book_path
          ctx.switch_to_edit_annotation(annotation, book_path) if annotation && book_path
          :handled
        },
      }

      bindings = Input::BindingGenerator.generate_for_mode(:annotations, custom_methods)
      bindings['d'] = lambda { |ctx, _|
        ctx.input_handler.delete_annotation(ctx.annotations_screen)
        :handled
      }

      @dispatcher.register_mode(:annotations, bindings)
    end

    def register_annotation_editor_bindings
      bindings = Input::BindingGenerator.generate_for_mode(:annotation_editor, {})
      bindings[:__default__] = lambda { |ctx, key|
        screen = ctx.instance_variable_get(:@annotation_editor_screen)
        result = screen.handle_input(key)
        if %i[saved cancelled].include?(result)
          # Refresh annotations data to show any changes
          ctx.instance_variable_get(:@annotations_screen).refresh_data
          ctx.switch_to_mode(:annotations)
        end
        :handled
      }

      @dispatcher.register_mode(:annotation_editor, bindings)
    end

    def handle_input(key)
      @input_handler.handle_input(key)
    end

    def handle_menu_input(key)
      @input_handler.handle_menu_input(key)
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
      books = @recent_screen.load_recent_books
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
