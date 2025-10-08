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
          cleanup_terminal

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
            handle_search_backspace
          else
            handle_file_backspace
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
          item = selected_library_item
          return unless item

          target_path = resolve_library_path(item)
          return state_controller.file_not_found unless target_path

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

        def cleanup_terminal
          terminal = menu.terminal_service
          return unless terminal

          cleanup_error = nil
          begin
            terminal.cleanup
          rescue StandardError => e
            cleanup_error = e
            resolve_logger&.error('Menu terminal cleanup failed', error: e.message)
          ensure
            force_cleanup_if_needed(terminal, cleanup_error)
          end
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

        def force_cleanup_if_needed(terminal, cleanup_error)
          return unless terminal.respond_to?(:force_cleanup)

          remaining_depth = EbookReader::Domain::Services::TerminalService.session_depth || 0
          needs_force = cleanup_error || remaining_depth.positive?
          return unless needs_force

          terminal.force_cleanup
        rescue StandardError => e
          resolve_logger&.error('Menu terminal force cleanup failed', error: e.message)
        end

        def handle_search_backspace
          current = (selectors.search_query(state) || '').to_s
          cursor = (state.get(%i[menu search_cursor]) || current.length).to_i
          return unless cursor.positive?

          prev = cursor - 1
          before = current[0, prev] || ''
          after  = current[cursor..] || ''
          state.dispatch(menu_action(search_query: before + after, search_cursor: prev))
        end

        def handle_file_backspace
          file_input = (selectors.file_input(state) || '').to_s
          return unless file_input.length.positive?

          new_val = file_input[0...-1]
          state.dispatch(menu_action(file_input: new_val))
        end

        def selected_library_item
          screen = menu.main_menu_component&.current_screen
          items = screen.respond_to?(:items) ? screen.items : []
          index = selectors.browse_selected(state) || 0
          items[index]
        end

        def resolve_library_path(item)
          primary = item.respond_to?(:open_path) ? item.open_path : nil
          return primary if state_controller.valid_cache_directory?(primary)

          fallback = item.respond_to?(:epub_path) ? item.epub_path : nil
          return fallback if fallback && !fallback.empty? && File.exist?(fallback)

          nil
        end
      end
    end
  end
end
