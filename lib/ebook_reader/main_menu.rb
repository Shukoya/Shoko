# frozen_string_literal: true

require_relative 'services/library_scanner'
require_relative 'mouseable_reader'
require_relative 'main_menu/actions/file_actions'
require_relative 'main_menu/actions/search_actions'
require_relative 'main_menu/actions/settings_actions'
require_relative 'input/dispatcher'
require_relative 'components/main_menu_component'
require_relative 'components/surface'
require_relative 'components/rect'

module EbookReader
  # Main menu (LazyVim style)
  class MainMenu
    include Actions::FileActions
    include Actions::SearchActions
    include Actions::SettingsActions
    include Input::KeyDefinitions::Helpers

    attr_reader :state, :input_handler, :filtered_epubs, :main_menu_component

    def config
      @state
    end

    def initialize
      setup_state
      setup_services
      setup_components
    end

    def run
      Terminal.setup
      @scanner.load_cached
      @filtered_epubs = @scanner.epubs || []
      @main_menu_component.browse_screen.filtered_epubs = @filtered_epubs
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
      @state.menu_mode = :browse
      @state.search_active = false
      # Search active state is now managed in GlobalState
      @dispatcher.activate(@state.menu_mode)
    end

    def switch_to_search
      @state.menu_mode = :search
      @state.search_active = true
      # Search active state is now managed in GlobalState
      @dispatcher.activate(@state.menu_mode)
    end

    def switch_to_mode(mode)
      @state.menu_mode = mode
      @state.browse_selected = 0 # Reset selection for all submenu modes
      @dispatcher.activate(@state.menu_mode)
    end

    def open_file_dialog
      @state.file_input = ''
      @open_file_screen.input = ''
      @state.menu_mode = :open_file
      @dispatcher.activate(@state.menu_mode)
    end

    def cleanup_and_exit(code, message, error = nil)
      Terminal.cleanup
      puts message
      puts error.backtrace if error && EPUBFinder::DEBUG_MODE
      exit code
    end

    def handle_browse_navigation(key)
      direction = case key
                  when "\e[A", 'k' then :up
                  when "\e[B", 'j' then :down
                  end
      @main_menu_component.browse_screen.navigate(direction) if direction
    end

    def handle_recent_input(key)
      @input_handler.handle_recent_input(key)
    end

    def handle_backspace_input
      if @state.search_active
        if @state.search_query.length.positive?
          @state.search_query = @state.search_query[0...-1]
          # Filtering is now handled automatically by the component through state observation
        end
      elsif @state.file_input.length.positive?
        @state.file_input = @state.file_input[0...-1]
      end
      @main_menu_component.open_file_screen.input = @state.file_input
    end

    def handle_character_input(key)
      char = key.to_s
      return unless char.length == 1 && char.ord >= 32

      @state.file_input = (@state.file_input + char)
      @main_menu_component.open_file_screen.input = @state.file_input
    end

    def switch_to_edit_annotation(_annotation, _book_path)
      # This functionality would need to be implemented in a component
      # For now, switch to annotations mode
      switch_to_mode(:annotations)
    end

    def refresh_scan
      @scanner.start_scan(force: true)
    end

    # Methods expected by BindingGenerator - MUST be public
    def handle_selection
      handle_menu_selection
    end

    def handle_cancel
      case @state.menu_mode
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
      case @state.menu_mode
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
      @state = Core::GlobalState.new
      @filtered_epubs = []
    end

    def setup_services
      # Use legacy services temporarily during migration
      @scanner = Services::LibraryScanner.new
      # Remove input_handler - replace with command system (TODO: Phase 2)
      @input_handler = Services::MainMenuInputHandler.new(self)
      setup_input_dispatcher
    end

    def setup_components
      @main_menu_component = Components::MainMenuComponent.new(self)
    end

    public

    # Legacy compatibility methods
    def browse_screen
      @main_menu_component.browse_screen
    end

    def recent_screen
      @main_menu_component.recent_screen
    end

    def settings_screen
      @main_menu_component.settings_screen
    end

    def open_file_screen
      @main_menu_component.open_file_screen
    end

    def annotations_screen
      @main_menu_component.annotations_screen
    end

    def annotation_editor_screen
      # This would need to be migrated to a component as well
      nil
    end

    def menu_screen
      @main_menu_component.current_screen
    end

    def selected_book
      @main_menu_component.browse_screen.selected_book
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
      @main_menu_component.browse_screen.filtered_epubs = @scanner.epubs
    end

    def navigate_browse(key)
      handle_browse_navigation(key)
    end

    def draw_screen
      height, width = Terminal.size
      Terminal.start_frame

      surface = Components::Surface.new(Terminal)
      bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      @main_menu_component.render(surface, bounds)

      Terminal.end_frame
    end

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      setup_consolidated_input_bindings
      @dispatcher.activate(@state.menu_mode)
    end

    def setup_consolidated_input_bindings
      # Register mode bindings using Input::CommandFactory patterns
      register_menu_bindings
      register_browse_bindings
      register_search_bindings
      register_recent_bindings
      register_settings_bindings
      register_open_file_bindings
      register_annotations_bindings
      register_annotation_editor_bindings
    end

    private

    def register_menu_bindings
      bindings = Input::CommandFactory.navigation_commands(nil, :selected, lambda { |_ctx|
        5 # 6 menu items (0-5)
      })
      bindings.merge!(Input::CommandFactory.menu_selection_commands)

      # Main menu quit (quit entire application)
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.cleanup_and_exit(0, '')
          :handled
        }
      end

      @dispatcher.register_mode(:menu, bindings)
    end

    def register_browse_bindings
      bindings = {}

      # Simple browse navigation
      Input::KeyDefinitions::NAVIGATION[:up].each do |key|
        bindings[key] = lambda do |ctx, _|
          current = ctx.state.browse_selected
          ctx.state.browse_selected = [current - 1, 0].max
          :handled
        end
      end
      Input::KeyDefinitions::NAVIGATION[:down].each do |key|
        bindings[key] = lambda do |ctx, _|
          current = ctx.state.browse_selected
          epubs = ctx.instance_variable_defined?(:@filtered_epubs) ? ctx.instance_variable_get(:@filtered_epubs) : []
          max_val = [(epubs&.length&.- 1), 0].max
          ctx.state.browse_selected = [current + 1, max_val].min
          :handled
        end
      end

      # Browse-specific selection: open selected book (only if books are available)
      Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
        bindings[key] = lambda do |ctx, _|
          epubs = ctx.instance_variable_defined?(:@filtered_epubs) ? ctx.instance_variable_get(:@filtered_epubs) : []
          ctx.open_selected_book if epubs && !epubs.empty?
          :handled
        end
      end

      # Exit browse mode
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:browse, bindings)
    end

    def register_search_bindings
      bindings = Input::CommandFactory.text_input_commands(:search_query)

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:search, bindings)
    end

    def register_recent_bindings
      # Use Input::CommandFactory with browse_selected for recent mode navigation
      bindings = Input::CommandFactory.navigation_commands(nil, :browse_selected, lambda { |ctx|
        (ctx.instance_variable_get(:@filtered_epubs)&.length || 1) - 1
      })

      # Recent-specific selection: open selected recent book
      Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.open_selected_book
          :handled
        }
      end

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:recent, bindings)
    end

    def register_settings_bindings
      # Use Input::CommandFactory with browse_selected for settings mode navigation
      bindings = Input::CommandFactory.navigation_commands(nil, :browse_selected, lambda { |_ctx|
        10 # Estimated settings options
      })

      # Settings-specific selection: handle setting change
      Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.handle_settings_input(key)
          :handled
        }
      end

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:settings, bindings)
    end

    def register_open_file_bindings
      bindings = Input::CommandFactory.text_input_commands(:file_input)

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:open_file, bindings)
    end

    def register_annotations_bindings
      # Use Input::CommandFactory with browse_selected for annotations mode navigation
      bindings = Input::CommandFactory.navigation_commands(nil, :browse_selected, lambda { |ctx|
        (ctx.state.annotations&.length || 1) - 1
      })

      # Annotations-specific selection: open/edit annotation
      Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
        bindings[key] = ->(_ctx, _) { :handled } # Placeholder for now
      end

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

      @dispatcher.register_mode(:annotations, bindings)
    end

    def register_annotation_editor_bindings
      bindings = Input::CommandFactory.text_input_commands(:search_query)

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end
      Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
        bindings[key] = lambda { |ctx, _|
          ctx.state.menu_mode = :menu
          :handled
        }
      end

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
      MouseableReader.new(path).run
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
        reader = MouseableReader.new(path)
        reader.run
      else
        @scanner.scan_message = 'Invalid file path'
        @scanner.scan_status = :error
      end
    end

    def load_recent_books
      RecentFiles.load
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
