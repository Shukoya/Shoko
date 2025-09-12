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
require_relative 'application/frame_coordinator'

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
      epubs = @scanner.epubs || []
      @filtered_epubs = epubs
      @main_menu_component.browse_screen.filtered_epubs = epubs
      @scanner.start_scan if epubs.empty?

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
          prev = cursor - 1
          before = current[0, prev] || ''
          after  = current[cursor..] || ''
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                            search_query: before + after,
                            search_cursor: prev
                          ))
        end
      else
        file_input = (EbookReader::Domain::Selectors::MenuSelectors.file_input(@state) || '').to_s
        if file_input.length.positive?
          new_val = file_input[0...-1]
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(file_input: new_val))
        end
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
      @frame_coordinator = Application::FrameCoordinator.new(@dependencies)
      @render_pipeline = Application::RenderPipeline.new(@dependencies)
      setup_input_dispatcher
    end

    def setup_components
      @main_menu_component = Components::MainMenuComponent.new(self, @dependencies)
    end

    public

    # Library mode helpers
    def library_up
      current = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      @state.dispatch(
        EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: (current - 1).clamp(0,
                                                                                                current))
      )
    end

    def library_down
      items = if @main_menu_component&.current_screen.respond_to?(:items)
                @main_menu_component.current_screen.items
              else
                []
              end
      max_index = [items.length - 1, 0].max
      current = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      @state.dispatch(
        EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: (current + 1).clamp(0,
                                                                                                max_index))
      )
    end

    def library_select
      screen = @main_menu_component&.current_screen
      items = screen.respond_to?(:items) ? screen.items : []
      index = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
      item = items[index]
      return unless item

      # Open using cache directory for instant open
      run_reader(item.open_path)
    end

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
      @terminal_service.read_keys_blocking(limit: 10)
    end

    def process_scan_results_if_available
      return unless (epubs = @scanner.process_results)

      @scanner.epubs = epubs
      @filtered_epubs = epubs
      @main_menu_component.browse_screen.filtered_epubs = epubs
    end

    def navigate_browse(key)
      handle_browse_navigation(key)
    end

    def draw_screen
      @frame_coordinator.with_frame do |surface, bounds, _w, _h|
        @render_pipeline.render_component(surface, bounds, @main_menu_component)
      end
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

    # Small helpers to reduce repeated binding patterns
    def add_back_bindings(bindings)
      keys = Array(Input::KeyDefinitions::ACTIONS[:quit]) + Array(Input::KeyDefinitions::ACTIONS[:cancel])
      keys.each { |k| bindings[k] = :back_to_menu }
      bindings
    end

    def add_confirm_bindings(bindings, action)
      Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = action }
      bindings
    end

    def add_nav_up_down(bindings, up_action, down_action)
      Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = up_action }
      Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = down_action }
      bindings
    end

    # Annotation helpers (public so dispatcher can invoke explicitly)
    def open_selected_annotation
      with_selected_annotation do |ann, path|
        # Prepare a pending jump for the reader to apply on startup
        @state.update({
                        %i[reader book_path] => path,
                        %i[reader pending_jump] => {
                          chapter_index: ann[:chapter_index],
                          selection_range: ann[:range] || nil,
                          annotation: ann,
                        },
                      })

        run_reader(path)
      end
    end

    def open_selected_annotation_for_edit
      with_selected_annotation do |ann, path|
        # Prepare in-menu editor state
        note_text = ann[:note] || ann['note'] || ''
        @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                          selected_annotation: ann,
                          selected_annotation_book: path,
                          annotation_edit_text: note_text,
                          annotation_edit_cursor: note_text.to_s.length
                        ))
        switch_to_mode(:annotation_editor)
      end
    end

    def delete_selected_annotation
      with_selected_annotation do |ann, path|
        ann_id = hid(ann)
        return unless ann_id

        service = @dependencies.resolve(:annotation_service)
        begin
          service.delete(path, ann_id)
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
        @main_menu_component.annotations_screen.refresh_data
      end
    end

    def save_current_annotation_edit
      ann = @state.get(%i[menu selected_annotation]) || {}
      path = @state.get(%i[menu selected_annotation_book])
      text = @state.get(%i[menu annotation_edit_text]) || ''
      return unless path && ann
      ann_id = hid(ann)
      return unless ann_id

      service = @dependencies.resolve(:annotation_service)
      begin
        service.update(path, ann_id, text)
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
      nav_up = Input::KeyDefinitions::NAVIGATION[:up]
      nav_down = Input::KeyDefinitions::NAVIGATION[:down]
      confirm_keys = Input::KeyDefinitions::ACTIONS[:confirm]
      quit_keys = Input::KeyDefinitions::ACTIONS[:quit]
      nav_up.each { |k| bindings[k] = :menu_up }
      nav_down.each { |k| bindings[k] = :menu_down }
      # Select current item
      confirm_keys.each { |k| bindings[k] = :menu_select }
      # Quit application from main menu
      quit_keys.each { |k| bindings[k] = :menu_quit }
      @dispatcher.register_mode(:menu, bindings)
    end

    def register_browse_bindings
      bindings = {}
      add_nav_up_down(bindings, :browse_up, :browse_down)
      add_confirm_bindings(bindings, :browse_select)
      add_back_bindings(bindings)
      # Start search with '/'
      bindings['/'] = :start_search
      @dispatcher.register_mode(:browse, bindings)
    end

    def register_search_bindings
      # Text input with cursor support; treat printable chars (including 'q') as input
      bindings = Input::CommandFactory.text_input_commands(:search_query, nil,
                                                           cursor_field: :search_cursor)

      # Navigation of filtered results via arrow keys only (not vi keys)
      arrow_up = ["\e[A", "\eOA"]
      arrow_down = ["\e[B", "\eOB"]
      arrow_up.each { |k| bindings[k] = :browse_up }
      arrow_down.each { |k| bindings[k] = :browse_down }

      # Open selected with Enter
      confirm_keys = Input::KeyDefinitions::ACTIONS[:confirm]
      confirm_keys.each { |k| bindings[k] = :browse_select }

      # Toggle exit search with '/'
      bindings['/'] = :exit_search

      @dispatcher.register_mode(:search, bindings)
    end

    # register_recent_bindings removed (no recent mode)

    def register_library_bindings
      bindings = {}
      add_nav_up_down(bindings, :library_up, :library_down)
      add_confirm_bindings(bindings, :library_select)
      add_back_bindings(bindings)
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
      add_back_bindings(bindings)

      @dispatcher.register_mode(:settings, bindings)
    end

    def register_open_file_bindings
      bindings = Input::CommandFactory.text_input_commands(:file_input)

      # Go back to main menu
      add_back_bindings(bindings)

      @dispatcher.register_mode(:open_file, bindings)
    end

    def register_annotations_bindings
      bindings = {}

      # Up/Down navigate within the annotations screen component
      add_nav_up_down(bindings, :annotations_up, :annotations_down)

      # Open selected annotation detail view
      add_confirm_bindings(bindings, :annotations_select)

      # Edit selected annotation (open book and enter editor)
      %w[e E].each { |k| bindings[k] = :annotations_edit }

      # Delete selected annotation
      bindings['d'] = :annotations_delete

      # Go back to main menu
      add_back_bindings(bindings)

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
      cancel_cmd = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.cancel
      Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = cancel_cmd }

      # Save: Ctrl+S and 'S'
      save_cmd = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.save
      bindings["\x13"] = save_cmd
      bindings['S'] = save_cmd

      # Backspace (both variants)
      backspace_cmd = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.backspace
      Input::KeyDefinitions::ACTIONS[:backspace].each { |k| bindings[k] = backspace_cmd }

      # Enter (CR and LF) + confirm keys
      enter_keys = []
      enter_keys += Array(Input::KeyDefinitions::ACTIONS[:enter]) if Input::KeyDefinitions::ACTIONS.key?(:enter)
      enter_keys += Array(EbookReader::Input::KeyDefinitions::ACTIONS[:confirm])
      enter_cmd = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.enter
      enter_keys.each { |k| bindings[k] = enter_cmd }

      # Default char input → insert
      bindings[:__default__] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.insert_char

      @dispatcher.register_mode(:annotation_editor, bindings)
    end

    # Legacy input handler removed; dispatcher handles all input

    # Duplicated file-open methods removed in favor of Actions::FileActions implementation

    # Provide current editor component for domain commands in menu context
    def current_editor_component
      return nil unless EbookReader::Domain::Selectors::MenuSelectors.mode(@state) == :annotation_editor

      @main_menu_component&.annotation_edit_screen
    end

    # file_not_found and handle_reader_error provided by Actions::FileActions

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
    # Indifferent access helpers for annotations
    def hget(h, key)
      h[key] || h[key.to_s]
    end

    def hid(h)
      hget(h, :id)
    end
    def selected_annotation_and_path
      screen = @main_menu_component.annotations_screen
      [screen.current_annotation, screen.current_book_path]
    end

    def with_selected_annotation
      ann, path = selected_annotation_and_path
      return unless ann && path
      yield ann, path
    end
