# frozen_string_literal: true

module EbookReader
  module Controllers
    module Menu
      # Encapsulates state mutations and view transitions for the menu UI.
      class UIController
        include EbookReader::Input::KeyDefinitions::Helpers

        def initialize(menu, state_controller)
          @menu = menu
          @state_controller = state_controller
          @state = menu.state
          @dependencies = menu.dependencies
        end

        def handle_menu_selection
          case selectors.selected(state)
          when 0 then switch_to_browse
          when 1 then switch_to_mode(:library)
          when 2 then switch_to_mode(:annotations)
          when 3 then open_file_dialog
          when 4 then switch_to_mode(:settings)
          when 5 then cleanup_and_exit(0, '')
          end
        end

        def handle_navigation(direction)
          current = selectors.selected(state)
          max_val = 5

          new_selected = case direction
                         when :up then [current - 1, 0].max
                         when :down then [current + 1, max_val].min
                         else current
                         end
          state.dispatch(menu_action(selected: new_selected))
        end

        def switch_to_browse
          state.dispatch(menu_action(mode: :browse, search_active: false))
          input_controller.activate(selectors.mode(state))
        end

        def switch_to_search
          state.dispatch(menu_action(mode: :search, search_active: true))
          input_controller.activate(selectors.mode(state))
        end

        def switch_to_mode(mode)
          state.dispatch(menu_action(mode: mode, browse_selected: 0))
          preload_annotations if mode == :annotations
          input_controller.activate(selectors.mode(state))
        end

        def open_file_dialog
          state.dispatch(menu_action(file_input: ''))
          menu.open_file_screen.input = ''
          state.dispatch(menu_action(mode: :open_file))
          input_controller.activate(selectors.mode(state))
        end

        def cleanup_and_exit(code, message, error = nil)
          menu.terminal_service.cleanup

          log_exit(message, error)
          exit code
        end

        def handle_browse_navigation(key)
          direction = case key
                      when "\e[A", 'k' then :up
                      when "\e[B", 'j' then :down
                      end
          menu.main_menu_component.browse_screen.navigate(direction) if direction
        end

        def handle_backspace_input
          if selectors.search_active?(state)
            current = (selectors.search_query(state) || '').to_s
            cursor = (state.get(%i[menu search_cursor]) || current.length).to_i
            if cursor.positive?
              prev = cursor - 1
              before = current[0, prev] || ''
              after  = current[cursor..] || ''
              state.dispatch(menu_action(search_query: before + after, search_cursor: prev))
            end
          else
            file_input = (selectors.file_input(state) || '').to_s
            if file_input.length.positive?
              new_val = file_input[0...-1]
              state.dispatch(menu_action(file_input: new_val))
            end
          end
          menu.open_file_screen.input = state.get(%i[menu file_input])
        end

        def handle_character_input(key)
          char = key.to_s
          return unless char.length == 1 && char.ord >= 32

          file_input = (selectors.file_input(state) || '').to_s
          state.dispatch(menu_action(file_input: file_input + char))
          menu.open_file_screen.input = state.get(%i[menu file_input])
        end

        def switch_to_edit_annotation(_annotation, _book_path)
          switch_to_mode(:annotations)
        end

        def handle_selection
          handle_menu_selection
        end

        def handle_cancel
          case selectors.mode(state)
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
          case selectors.mode(state)
          when :browse
            menu.handle_delete if menu.respond_to?(:handle_delete)
          end
        end

        def library_up
          current = selectors.browse_selected(state) || 0
          state.dispatch(menu_action(browse_selected: (current - 1).clamp(0, current)))
        end

        def library_down
          items = if menu.main_menu_component&.current_screen.respond_to?(:items)
                    menu.main_menu_component.current_screen.items
                  else
                    []
                  end
          max_index = [items.length - 1, 0].max
          current = selectors.browse_selected(state) || 0
          state.dispatch(menu_action(browse_selected: (current + 1).clamp(0, max_index)))
        end

        def library_select
          screen = menu.main_menu_component&.current_screen
          items = screen.respond_to?(:items) ? screen.items : []
          index = selectors.browse_selected(state) || 0
          item = items[index]
          return unless item

          target_path = item.open_path
          unless state_controller.valid_cache_directory?(target_path)
            alt_path = item.respond_to?(:epub_path) ? item.epub_path : nil
            if alt_path && !alt_path.empty? && File.exist?(alt_path)
              target_path = alt_path
            else
              state_controller.file_not_found
              return
            end
          end

          state_controller.run_reader(target_path)
        end

        private

        attr_reader :menu, :state_controller, :state, :dependencies

        def log_exit(message, error)
          logger = resolve_logger
          logger&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
          return unless error

          logger&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
        end

        def selectors
          EbookReader::Domain::Selectors::MenuSelectors
        end

        def resolve_logger
          dependencies.resolve(:logger)
        rescue StandardError
          nil
        end

        def menu_action(payload)
          EbookReader::Domain::Actions::UpdateMenuAction.new(payload)
        end

        def input_controller
          menu.input_controller
        end

        def preload_annotations
          service = dependencies.resolve(:annotation_service)
          state.dispatch(menu_action(annotations_all: service.list_all))
        rescue StandardError
          state.dispatch(menu_action(annotations_all: {}))
        end
      end
    end
  end
end
