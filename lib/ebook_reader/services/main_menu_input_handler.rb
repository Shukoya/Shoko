# frozen_string_literal: true

module EbookReader
  module Services
    # Handles all key input for MainMenu so the menu class focuses
    # on rendering and high level actions.
    class MainMenuInputHandler
      include Concerns::InputHandler

      def initialize(menu)
        @menu = menu
      end

      def handle_input(key)
        return unless key

        mode = @menu.instance_variable_get(:@mode)
        mode_handler = "handle_#{mode}_input"

        send(mode_handler, key) if respond_to?(mode_handler, true)
      end

      def handle_menu_input(key)
        case key
        when 'q', 'Q' then handle_quit
        when 'f', 'F' then @menu.send(:switch_to_browse)
        when 'r', 'R' then @menu.send(:switch_to_mode, :recent)
        when 'o', 'O' then @menu.send(:open_file_dialog)
        when 's', 'S' then @menu.send(:switch_to_mode, :settings)
        else handle_menu_navigation(key)
        end
      end

      def handle_menu_navigation(key)
        case key
        when *navigation_down_keys then navigate_menu_down
        when *navigation_up_keys then navigate_menu_up
        when *enter_keys then @menu.send(:handle_menu_selection)
        end
      end

      private

      def handle_quit
        @menu.send(:cleanup_and_exit, 0, '')
      end

      def navigation_down_keys
        ['j', "\e[B", "\eOB"]
      end

      def navigation_up_keys
        ['k', "\e[A", "\eOA"]
      end

      def enter_keys
        ["\r", "\n"]
      end

      def navigate_menu_down
        selected = (@menu.instance_variable_get(:@selected) + 1) % 5
        @menu.instance_variable_set(:@selected, selected)
      end

      def navigate_menu_up
        selected = (@menu.instance_variable_get(:@selected) - 1 + 5) % 5
        @menu.instance_variable_set(:@selected, selected)
      end

      def handle_browse_input(key)
        handler = browse_input_handlers[key]

        if handler
          handler.call
        elsif navigation_key?(key)
          @menu.send(:navigate_browse, key)
        elsif searchable_key?(key)
          add_to_search(key)
        end
      end

      def browse_input_handlers
        @browse_input_handlers ||= begin
          merged = base_browse_handlers.merge(cursor_handlers)
          merged.merge(backspace_handlers)
        end
      end

      def base_browse_handlers
        {}.merge(
          refresh_handlers,
          navigation_handlers,
          action_handlers
        )
      end

      def refresh_handlers
        {
          'r' => -> { @menu.send(:refresh_scan) },
          'R' => -> { @menu.send(:refresh_scan) },
        }
      end

      def navigation_handlers
        {
          "\r" => -> { @menu.send(:open_selected_book) },
          "\n" => -> { @menu.send(:open_selected_book) },
          '/' => -> { reset_search },
        }
      end

      def action_handlers
        handlers = { "\e[3~" => -> { @menu.send(:handle_delete) } }
        switch_keys.each do |key|
          handlers[key] = -> { @menu.send(:switch_to_mode, :menu) }
        end
        handlers
      end

      def switch_keys
        ["\e", "\x1B", 'q']
      end

      def cursor_handlers
        {
          "\e[D" => -> { @menu.send(:move_search_cursor, -1) },
          "\eOD" => -> { @menu.send(:move_search_cursor, -1) },
          "\e[C" => -> { @menu.send(:move_search_cursor, 1) },
          "\eOC" => -> { @menu.send(:move_search_cursor, 1) },
        }
      end

      def backspace_handlers
        backspace_keys.to_h { |k| [k, -> { handle_backspace }] }
      end

      def backspace_keys
        ["\b", "\x7F"]
      end

      def reset_search
        @menu.instance_variable_set(:@search_query, '')
        @menu.instance_variable_set(:@search_cursor, 0)
      end

      def handle_recent_input(key)
        recent = @menu.send(:load_recent_books)

        if escape_key?(key)
          @menu.send(:switch_to_mode, :menu)
        elsif navigation_key?(key) && recent.any?
          handle_recent_navigation(key, recent)
        elsif enter_key?(key)
          handle_recent_selection(recent)
        end
      end

      def handle_recent_navigation(key, recent)
        selected = handle_navigation_keys(
          key,
          @menu.instance_variable_get(:@browse_selected),
          recent.length - 1
        )
        @menu.instance_variable_set(:@browse_selected, selected)
      end

      def handle_recent_selection(recent)
        book = recent[@menu.instance_variable_get(:@browse_selected)]

        if valid_book?(book)
          @menu.send(:open_book, book['path'])
        else
          show_file_not_found_error
        end
      end

      def valid_book?(book)
        book && book['path'] && File.exist?(book['path'])
      end

      def show_file_not_found_error
        scanner = @menu.instance_variable_get(:@scanner)
        scanner.scan_message = 'File not found'
        scanner.scan_status = :error
      end

      def handle_settings_input(key)
        if escape_key?(key)
          @menu.send(:switch_to_mode, :menu)
          @menu.instance_variable_get(:@config).save
        else
          handle_setting_change(key)
        end
      end

      def handle_setting_change(key)
        actions = {
          '1' => :toggle_view_mode,
          '2' => :toggle_page_numbers,
          '3' => :cycle_line_spacing,
          '4' => :toggle_highlight_quotes,
          '5' => :clear_cache,
          '6' => :toggle_page_numbering_mode,
        }
        @menu.send(actions[key]) if actions[key]
      end

      def searchable_key?(key)
        return false unless key

        begin
          key = key.to_s.force_encoding('UTF-8')
          key.valid_encoding? && key =~ /[a-zA-Z0-9 .-]/
        rescue StandardError
          false
        end
      end

      def handle_backspace
        query = @menu.instance_variable_get(:@search_query).dup
        cursor = @menu.instance_variable_get(:@search_cursor)
        return if cursor <= 0

        query.slice!(cursor - 1)
        @menu.instance_variable_set(:@search_query, query)
        @menu.instance_variable_set(:@search_cursor, cursor - 1)
        @menu.send(:filter_books)
      end

      def add_to_search(key)
        query = @menu.instance_variable_get(:@search_query).dup
        cursor = @menu.instance_variable_get(:@search_cursor)
        query.insert(cursor, key)
        @menu.instance_variable_set(:@search_query, query)
        @menu.instance_variable_set(:@search_cursor, cursor + 1)
        @menu.send(:filter_books)
      end

      def handle_open_file_input(key)
        @menu.send(:handle_open_file_input, key)
      end

      public :handle_browse_input,
             :handle_recent_input,
             :handle_setting_change,
             :searchable_key?
    end
  end
end
