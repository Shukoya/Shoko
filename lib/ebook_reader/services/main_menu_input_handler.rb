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

        state = @menu.instance_variable_get(:@state)
        handlers = handlers_for_mode(state.mode)
        (handlers[key] || handlers[:__default__])&.call(key)
      end

      def handlers_for_mode(mode)
        case mode
        when :menu then menu_handlers
        when :browse then browse_handlers
        when :recent then recent_handlers
        when :settings then settings_handlers
        when :annotations then annotations_handlers
        when :annotation_editor then annotation_editor_handlers
        when :open_file then open_file_handlers
        else {}
        end
      end

      def menu_handlers
        handlers = {}
        # Primary actions
        { 'q' => ->(_) { handle_quit }, 'Q' => ->(_) { handle_quit },
          'f' => ->(_) { @menu.send(:switch_to_browse) }, 'F' => lambda { |_|
                                                            @menu.send(:switch_to_browse)
                                                          },
          'r' => ->(_) { @menu.send(:switch_to_mode, :recent) }, 'R' => lambda { |_|
                                                                   @menu.send(:switch_to_mode, :recent)
                                                                 },
          'o' => ->(_) { @menu.send(:open_file_dialog) }, 'O' => lambda { |_|
                                                            @menu.send(:open_file_dialog)
                                                          },
          's' => ->(_) { @menu.send(:switch_to_mode, :settings) }, 'S' => lambda { |_|
                                                                     @menu.send(:switch_to_mode, :settings)
                                                                   } }.each do |k, v|
          handlers[k] =
            v
        end

        # Navigation within menu
        navigation_down_keys.each { |k| handlers[k] = ->(_) { navigate_menu_down } }
        navigation_up_keys.each { |k| handlers[k] = ->(_) { navigate_menu_up } }
        enter_keys.each { |k| handlers[k] = ->(_) { @menu.send(:handle_menu_selection) } }

        handlers
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

      def handle_recent_input(key)
        if escape_key?(key)
          @menu.send(:switch_to_mode, :menu)
          return
        end

        recent_screen = @menu.instance_variable_get(:@recent_screen)
        state = @menu.instance_variable_get(:@state)
        # Use MainMenu's helper to respect RecentScreen's method visibility
        recent_books = @menu.send(:load_recent_books)

        return if recent_books.empty?

        if navigation_key?(key)
          new_selection = handle_navigation_keys(key, state.browse_selected, recent_books.size - 1)
          state.browse_selected = new_selection
        elsif enter_key?(key)
          selected_book = recent_books[state.browse_selected]
          if selected_book && selected_book['path']
            @menu.send(:open_book, selected_book['path'])
          end
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
        state = @menu.instance_variable_get(:@state)
        state.selected = (state.selected + 1) % 5
      end

      def navigate_menu_up
        state = @menu.instance_variable_get(:@state)
        state.selected = (state.selected - 1 + 5) % 5
      end

      def browse_handlers
        handlers = {}
        # Refresh
        %w[r R].each { |k| handlers[k] = ->(_) { @menu.send(:refresh_scan) } }
        # Open selection
        ["\r", "\n"].each { |k| handlers[k] = ->(_) { @menu.send(:open_selected_book) } }
        # Start search
        handlers['/'] = ->(_) { reset_search }
        # Delete key
        handlers["\e[3~"] = ->(_) { @menu.send(:handle_delete) }
        # Switch back
        switch_keys.each { |k| handlers[k] = ->(_) { @menu.send(:switch_to_mode, :menu) } }
        # Cursor left/right for search
        cursor_handlers.each { |k, v| handlers[k] = ->(_) { v.call } }
        # Backspace handling
        backspace_keys.each { |k| handlers[k] = ->(_) { handle_backspace } }
        # Navigation
        ['j', "\e[B", "\eOB", 'k', "\e[A", "\eOA"].each do |k|
          handlers[k] = ->(key) { @menu.send(:navigate_browse, key) }
        end
        # Default: searchable text input
        handlers[:__default__] = ->(k) { add_to_search(k) if searchable_key?(k) }
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
        state = @menu.instance_variable_get(:@state)
        state.search_query = ''
        state.search_cursor = 0
      end

      def recent_handlers
        { __default__: ->(k) { handle_recent_input(k) } }
      end

      def handle_recent_navigation(key, recent)
        state = @menu.instance_variable_get(:@state)
        selected = handle_navigation_keys(key, state.browse_selected, recent.length - 1)
        state.browse_selected = selected
      end

      def handle_recent_selection(recent)
        book = recent[@menu.instance_variable_get(:@state).browse_selected]

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

      def settings_handlers
        handlers = { "\e" => lambda { |_|
          @menu.send(:switch_to_mode, :menu)
          @menu.instance_variable_get(:@config).save
        } }
        # Numeric toggles
        {
          '1' => :toggle_view_mode,
          '2' => :toggle_page_numbers,
          '3' => :cycle_line_spacing,
          '4' => :toggle_highlight_quotes,
          '5' => :clear_cache,
          '6' => :toggle_page_numbering_mode,
        }.each do |k, action|
          handlers[k] = ->(_) { @menu.send(action) }
        end
        handlers
      end

      def annotations_handlers
        screen = @menu.instance_variable_get(:@annotations_screen)
        handlers = {}
        # Exit
        ['q', "\e"].each { |k| handlers[k] = ->(_) { @menu.send(:switch_to_mode, :menu) } }
        # Navigation
        ['j', "\e[B"].each { |k| handlers[k] = ->(_) { navigate_annotations_down(screen) } }
        ['k', "\e[A"].each { |k| handlers[k] = ->(_) { navigate_annotations_up(screen) } }
        # Delete
        handlers['d'] = ->(_) { delete_annotation(screen) }
        # Enter
        ["\r", "\n"].each do |k|
          handlers[k] = lambda { |_|
            annotation = screen.current_annotation
            book_path = screen.current_book_path
            @menu.send(:switch_to_edit_annotation, annotation, book_path) if annotation && book_path
          }
        end
        handlers
      end

      def annotation_editor_handlers
        screen = @menu.instance_variable_get(:@annotation_editor_screen)
        {
          __default__: lambda do |k|
            result = screen.handle_input(k)
            next unless %i[saved cancelled].include?(result)

            @menu.instance_variable_get(:@annotations_screen).send(:initialize)
            @menu.send(:switch_to_mode, :annotations)
          end,
        }
      end

      def delete_annotation(screen)
        # For now, this is a placeholder.
        # A confirmation dialog should be added here.
        book_path = screen.instance_variable_get(:@books)[screen.selected_book_index]
        return unless book_path

        annotations = screen.instance_variable_get(:@annotations_by_book)[book_path]
        annotation = annotations[screen.selected_annotation_index]

        return unless annotation

        EbookReader::Annotations::AnnotationStore.delete(book_path, annotation['id'])
        # Refresh annotations
        new_annotations = EbookReader::Annotations::AnnotationStore.send(:load_all)
        screen.instance_variable_set(:@annotations_by_book, new_annotations)
        screen.instance_variable_set(:@books, new_annotations.keys)
        screen.selected_book_index = [screen.selected_book_index, screen.book_count - 1].max
        return unless screen.selected_book_index >= 0

        screen.selected_annotation_index = [screen.selected_annotation_index,
                                            screen.annotation_count_for_selected_book - 1].max
      end

      def edit_annotation(screen)
        # This is a placeholder for now.
        # It needs to launch the annotation editor.
      end

      def navigate_annotations_down(screen)
        book_count = screen.book_count
        return if book_count.zero?

        annotation_count = screen.annotation_count_for_selected_book

        if screen.selected_annotation_index < annotation_count - 1
          screen.selected_annotation_index += 1
        elsif screen.selected_book_index < book_count - 1
          screen.selected_book_index += 1
          screen.selected_annotation_index = 0
        end
      end

      def navigate_annotations_up(screen)
        book_count = screen.book_count
        return if book_count.zero?

        if screen.selected_annotation_index.positive?
          screen.selected_annotation_index -= 1
        elsif screen.selected_book_index.positive?
          screen.selected_book_index -= 1
          screen.selected_annotation_index = screen.annotation_count_for_selected_book - 1
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

      def open_file_handlers
        { __default__: ->(k) { @menu.send(:handle_open_file_input, k) } }
      end

      public :handle_setting_change,
             :searchable_key?
    end
  end
end
