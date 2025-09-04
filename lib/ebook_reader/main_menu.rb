# frozen_string_literal: true

require_relative 'infrastructure/library_scanner'
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

    attr_reader :state, :filtered_epubs, :main_menu_component, :scanner

    def config
      @state
    end

    def initialize(dependencies = nil)
      @dependencies = dependencies || Domain::ContainerFactory.create_default_container
      setup_state
      setup_services
      setup_components
    end

    def run
      @terminal_service.setup
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
      case EbookReader::Domain::Selectors::MenuSelectors.selected(@state)
      when 0 then switch_to_browse
      when 1 then switch_to_mode(:library)
      when 2 then switch_to_mode(:annotations)
      when 3 then open_file_dialog
      when 4 then switch_to_mode(:settings)
      when 5 then cleanup_and_exit(0, '')
      end
    end

    def handle_navigation(direction)
      current = EbookReader::Domain::Selectors::MenuSelectors.selected(@state)
      max_val = 5 # 6 menu items (0-5)

      new_selected = case direction
                     when :up then [current - 1, 0].max
                     when :down then [current + 1, max_val].min
                     else current
                     end
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(selected: new_selected))
    end

    def switch_to_browse
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :browse,
                                                                         search_active: false))
      # Search active state is now managed in the central StateStore
      @dispatcher.activate(EbookReader::Domain::Selectors::MenuSelectors.mode(@state))
    end

    def switch_to_search
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :search,
                                                                         search_active: true))
      # Search active state is now managed in the central StateStore
      @dispatcher.activate(EbookReader::Domain::Selectors::MenuSelectors.mode(@state))
    end

    def switch_to_mode(mode)
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: mode,
                                                                         browse_selected: 0))
      if mode == :annotations
        # Preload all annotations into state for the screen component
        begin
          service = @dependencies.resolve(:annotation_service)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(annotations_all: service.list_all))
        rescue StandardError
          # Best-effort; if service unavailable, leave empty
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(annotations_all: {}))
        end
      end
      @dispatcher.activate(EbookReader::Domain::Selectors::MenuSelectors.mode(@state))
    end

    def open_file_dialog
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(file_input: ''))
      @open_file_screen.input = ''
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :open_file))
      @dispatcher.activate(EbookReader::Domain::Selectors::MenuSelectors.mode(@state))
    end

    def cleanup_and_exit(code, message, error = nil)
      @terminal_service.cleanup
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

    def handle_backspace_input
      if EbookReader::Domain::Selectors::MenuSelectors.search_active?(@state)
        current = (EbookReader::Domain::Selectors::MenuSelectors.search_query(@state) || '').to_s
        cursor = (@state.get(%i[menu search_cursor]) || current.length).to_i
        if cursor.positive?
          before = current[0, cursor - 1] || ''
          after  = current[cursor..] || ''
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                            search_query: before + after,
                            search_cursor: cursor - 1
                          ))
        end
      elsif @state.get(%i[menu file_input]).length.positive?
        file_input = (EbookReader::Domain::Selectors::MenuSelectors.file_input(@state) || '').to_s
        new_val = file_input.length.positive? ? file_input[0...-1] : file_input
        @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(file_input: new_val))
      end
      @main_menu_component.open_file_screen.input = @state.get(%i[menu file_input])
    end

    def handle_character_input(key)
      char = key.to_s
      return unless char.length == 1 && char.ord >= 32

      file_input = (EbookReader::Domain::Selectors::MenuSelectors.file_input(@state) || '').to_s
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(file_input: file_input + char))
      @main_menu_component.open_file_screen.input = @state.get(%i[menu file_input])
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
      case EbookReader::Domain::Selectors::MenuSelectors.mode(@state)
      when :menu
        cleanup_and_exit(0, '')
      when :browse, :settings, :annotations, :annotation_editor, :open_file
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
      case EbookReader::Domain::Selectors::MenuSelectors.mode(@state)
      when :browse
        handle_delete if respond_to?(:handle_delete)
      else
        # No-op for other modes
      end
    end

    # Settings are handled directly via dispatcher bindings

    private

    def setup_state
      @state = @dependencies.resolve(:global_state)
      @filtered_epubs = []
    end

    def setup_services
      # Use dependency injection for services
      @scanner = @dependencies.resolve(:library_scanner)
      @terminal_service = @dependencies.resolve(:terminal_service)
      setup_input_dispatcher
    end

    def setup_components
      @main_menu_component = Components::MainMenuComponent.new(self, @dependencies)
    end

    public

    # Legacy compatibility methods
    def browse_screen
      @main_menu_component.browse_screen
    end

    # recent_screen removed

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
      @main_menu_component.annotation_edit_screen
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
      key = @terminal_service.read_key_blocking
      keys = [key]
      collect_additional_keys(keys)
      keys
    end

    def collect_additional_keys(keys)
      while (extra = @terminal_service.read_key)
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
      height, width = @terminal_service.size
      @terminal_service.start_frame

      surface = @terminal_service.create_surface
      bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
      @main_menu_component.render(surface, bounds)

      @terminal_service.end_frame
    end

    def setup_input_dispatcher
      @dispatcher = Input::Dispatcher.new(self)
      setup_consolidated_input_bindings
      @dispatcher.activate(EbookReader::Domain::Selectors::MenuSelectors.mode(@state))
    end

    def setup_consolidated_input_bindings
      # Register mode bindings using Input::CommandFactory patterns
      register_menu_bindings
      register_browse_bindings
      register_search_bindings
      # recent bindings removed
      register_library_bindings
      register_settings_bindings
      register_open_file_bindings
      register_annotations_bindings
      register_annotation_detail_bindings
      register_annotation_editor_bindings
    end

    # Annotation helpers (public so dispatcher can invoke explicitly)
    def open_selected_annotation
      screen = @main_menu_component.annotations_screen
      annotation = screen.current_annotation
      path = screen.current_book_path
      return unless annotation && path

      # Prepare a pending jump for the reader to apply on startup
      @state.update({
                      %i[reader book_path] => path,
                      %i[reader pending_jump] => {
                        chapter_index: annotation[:chapter_index],
                        selection_range: annotation[:range] || nil,
                        annotation: annotation,
                      },
                    })

      run_reader(path)
    end

    def open_selected_annotation_for_edit
      screen = @main_menu_component.annotations_screen
      annotation = screen.current_annotation
      path = screen.current_book_path
      return unless annotation && path

      # Prepare in-menu editor state
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
        selected_annotation: annotation,
        selected_annotation_book: path,
        annotation_edit_text: (annotation[:note] || annotation['note'] || ''),
        annotation_edit_cursor: (annotation[:note] || annotation['note'] || '').to_s.length,
      ))
      switch_to_mode(:annotation_editor)
    end

    def delete_selected_annotation
      screen = @main_menu_component.annotations_screen
      annotation = screen.current_annotation
      path = screen.current_book_path
      return unless annotation && path && annotation[:id]

      service = @dependencies.resolve(:annotation_service)
      begin
        service.delete(path, annotation[:id])
        # Refresh preloaded mapping for list view
        @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(annotations_all: service.list_all))
      rescue StandardError => e
        # Log error; do not fallback to direct store
        begin
          @dependencies.resolve(:logger).error('Failed to delete annotation', error: e.message,
                                                                              path: path)
        rescue StandardError
          # no-op
        end
      end

      # Refresh UI
      screen.refresh_data
    end

    def save_current_annotation_edit
      ann = @state.get(%i[menu selected_annotation]) || {}
      path = @state.get(%i[menu selected_annotation_book])
      text = @state.get(%i[menu annotation_edit_text]) || ''
      return unless path && ann && (ann[:id] || ann['id'])

      service = @dependencies.resolve(:annotation_service)
      begin
        service.update(path, ann[:id] || ann['id'], text)
        # Refresh all annotations mapping for list view
        @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(annotations_all: service.list_all))
      rescue StandardError => e
        # Log error; do not fallback to direct store
        begin
          @dependencies.resolve(:logger).error('Failed to update annotation', error: e.message,
                                                                              path: path)
        rescue StandardError
          # no-op
        end
      end

      switch_to_mode(:annotations)
      @main_menu_component.annotations_screen.refresh_data
    end

    private

    # Removed unused helper methods (create_menu_navigation_commands, create_browse_navigation_commands)

    def register_menu_bindings
      bindings = {}
      # Up/Down navigation via domain menu commands
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :menu_up }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :menu_down }
      # Select current item
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :menu_select }
      # Quit application from main menu
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :menu_quit }
      @dispatcher.register_mode(:menu, bindings)
    end

    def register_browse_bindings
      bindings = {}
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :browse_up }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :browse_down }
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :browse_select }
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }
      # Start search with '/'
      bindings['/'] = :start_search
      @dispatcher.register_mode(:browse, bindings)
    end

    def register_search_bindings
      # Text input with cursor support; treat printable chars (including 'q') as input
      bindings = Input::CommandFactory.text_input_commands(:search_query, nil,
                                                           cursor_field: :search_cursor)

      # Navigation of filtered results via arrow keys only (not vi keys)
      ["\e[A", "\eOA"].each { |k| bindings[k] = :browse_up }
      ["\e[B", "\eOB"].each { |k| bindings[k] = :browse_down }

      # Open selected with Enter
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :browse_select }

      # Toggle exit search with '/'
      bindings['/'] = :exit_search

      @dispatcher.register_mode(:search, bindings)
    end

    def register_recent_bindings
      bindings = {}
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :recent_up }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :recent_down }
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :recent_select }
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }
      @dispatcher.register_mode(:recent, bindings)
    end

    def register_library_bindings
      bindings = {}
      # Navigate
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :library_up }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :library_down }
      # Open
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :library_select }
      # Back
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }
      @dispatcher.register_mode(:library, bindings)
    end

    def register_settings_bindings
      bindings = {}

      # Number keys for settings toggles
      # 1: View Mode
      bindings['1'] = :toggle_view_mode
      # 2: Line Spacing
      bindings['2'] = :cycle_line_spacing
      # 3: Page Numbers
      bindings['3'] = :toggle_page_numbers
      # 4: Page Numbering Mode
      bindings['4'] = :toggle_page_numbering_mode
      # 5: Highlight Quotes
      bindings['5'] = :toggle_highlight_quotes
      # 6: Wipe Cache
      bindings['6'] = :wipe_cache

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }

      @dispatcher.register_mode(:settings, bindings)
    end

    def register_open_file_bindings
      bindings = Input::CommandFactory.text_input_commands(:file_input)

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }

      @dispatcher.register_mode(:open_file, bindings)
    end

    def register_annotations_bindings
      bindings = {}

      # Up/Down navigate within the annotations screen component
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :annotations_up }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :annotations_down }

      # Open selected annotation detail view
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :annotations_select }

      # Edit selected annotation (open book and enter editor)
      %w[e E].each { |k| bindings[k] = :annotations_edit }

      # Delete selected annotation
      bindings['d'] = :annotations_delete

      # Go back to main menu
      Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = :back_to_menu }
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :back_to_menu }

      @dispatcher.register_mode(:annotations, bindings)
    end

    def register_annotation_detail_bindings
      bindings = {}

      # Actions from detail view
      %w[o O].each { |k| bindings[k] = :annotation_detail_open }
      %w[e E].each { |k| bindings[k] = :annotation_detail_edit }
      bindings['d'] = :annotation_detail_delete

      # Back to annotations list
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :annotation_detail_back }

      @dispatcher.register_mode(:annotation_detail, bindings)
    end

    def register_annotation_editor_bindings
      bindings = {}

      # Cancel
      Input::KeyDefinitions::ACTIONS[:cancel].each do |k|
        bindings[k] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.cancel
      end

      # Save: Ctrl+S and 'S'
      bindings["\x13"] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.save
      bindings['S'] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.save

      # Backspace (both variants)
      Input::KeyDefinitions::ACTIONS[:backspace].each do |k|
        bindings[k] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.backspace
      end

      # Enter (CR and LF)
      if Input::KeyDefinitions::ACTIONS.key?(:enter)
        Input::KeyDefinitions::ACTIONS[:enter].each do |k|
          bindings[k] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.enter
        end
      end
      EbookReader::Input::KeyDefinitions::ACTIONS[:confirm].each do |k|
        bindings[k] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.enter
      end

      # Default char input → insert
      bindings[:__default__] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.insert_char

      @dispatcher.register_mode(:annotation_editor, bindings)
    end

    # Legacy input handler removed; dispatcher handles all input

    # Duplicated file-open methods removed in favor of Actions::FileActions implementation

    # Provide current editor component for domain commands in menu context
    def current_editor_component
      unless EbookReader::Domain::Selectors::MenuSelectors.mode(@state) == :annotation_editor
        return nil
      end

      @main_menu_component&.annotation_edit_screen
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

    # Use Actions::FileActions#sanitize_input_path and #handle_file_path

    def load_recent_books
      RecentFiles.load
    end

    def handle_dialog_error(error)
      puts "Error: #{error.message}"
      sleep 2
      @terminal_service.setup
    end

    def time_ago_in_words(time)
      return 'unknown' unless time

      seconds = Time.now - time
      format_time_ago(seconds, time)
    rescue StandardError
      'unknown'
    end

    # Library mode helpers
    public def library_up
      current = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: [current - 1, 0].max))
    end

    public def library_down
      items = if @main_menu_component&.current_screen&.respond_to?(:items)
                @main_menu_component.current_screen.items
              else
                []
              end
      max_index = [items.length - 1, 0].max
      current = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: [current + 1, max_index].min))
    end

    public def library_select
      screen = @main_menu_component&.current_screen
      items = screen&.respond_to?(:items) ? screen.items : []
      index = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      item = items[index]
      return unless item

      # Open using cache directory for instant open
      run_reader(item.open_path)
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
