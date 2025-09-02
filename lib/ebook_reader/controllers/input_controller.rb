# frozen_string_literal: true

module EbookReader
  module Controllers
    # Handles all input processing: key handling, popup management, mode switching
    class InputController
      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @dispatcher = nil
      end

      def setup_input_dispatcher(reader_controller)
        @dispatcher = Input::Dispatcher.new(reader_controller)
        setup_consolidated_reader_bindings(reader_controller)
        @dispatcher.activate_stack([:read])
      end

      def handle_key(key)
        @dispatcher&.handle_key(key)
      end

      # Enhanced popup navigation handlers for direct key routing
      def handle_popup_navigation(key)
        popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
        return :pass unless popup_menu

        result = popup_menu.handle_key(key)

        if result && result[:type] == :selection_change
          :handled
        else
          :pass
        end
      end

      def handle_popup_action_key(key)
        popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
        return :pass unless popup_menu

        result = popup_menu.handle_key(key)
        if result && result[:type] == :action
          ui_controller = @dependencies.resolve(:ui_controller)
          ui_controller.handle_popup_action(result)
          :handled
        else
          :pass
        end
      end

      def handle_popup_cancel(key)
        popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
        return :pass unless popup_menu

        result = popup_menu.handle_key(key)
        if result && result[:type] == :cancel
          ui_controller = @dependencies.resolve(:ui_controller)
          ui_controller.cleanup_popup_state
          ui_controller.switch_mode(:read)
          :handled
        else
          :pass
        end
      end

      def handle_popup_menu_input(keys)
        popup_menu = EbookReader::Domain::Selectors::ReaderSelectors.popup_menu(@state)
        return unless popup_menu

        ui_controller = @dependencies.resolve(:ui_controller)
        keys.each do |key|
          result = popup_menu.handle_key(key)
          next unless result

          case result[:type]
          when :selection_change
            # Selection change handled by popup itself
          when :action
            ui_controller.handle_popup_action(result)
          when :cancel
            ui_controller.cleanup_popup_state
            ui_controller.switch_mode(:read)
          end
        end
      end

      private

      def setup_consolidated_reader_bindings(reader_controller)
        # Register reader mode bindings using Input::CommandFactory patterns
        register_read_bindings(reader_controller)
        register_popup_menu_bindings(reader_controller)

        # Keep legacy bindings for modes not yet converted
        register_help_bindings_new(reader_controller)
        register_toc_bindings_new(reader_controller)
        register_bookmarks_bindings_new(reader_controller)
        register_annotation_editor_bindings_new(reader_controller)
      end

      def register_read_bindings(_reader_controller)
        bindings = Input::CommandFactory.reader_navigation_commands
        bindings.merge!(Input::CommandFactory.reader_control_commands)

        # When sidebar is visible, redirect up/down/enter to sidebar handlers
        Input::KeyDefinitions::NAVIGATION[:down].each do |key|
          bindings[key] = :conditional_down
        end

        Input::KeyDefinitions::NAVIGATION[:up].each do |key|
          bindings[key] = :conditional_up
        end

        Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
          bindings[key] = :conditional_select
        end

        # Ensure TOC toggle is bound explicitly and marked handled
        %w[t T].each do |key|
          bindings[key] = :open_toc
        end

        @dispatcher.register_mode(:read, bindings)
      end

      def register_popup_menu_bindings(_reader_controller)
        # Popup menu navigation is now handled directly in main_loop via handle_popup_menu_input
        bindings = {}
        bindings.merge!(Input::CommandFactory.menu_selection_commands)
        bindings.merge!(Input::CommandFactory.exit_commands(:exit_popup_menu))
        @dispatcher.register_mode(:popup_menu, bindings)
      end

      def register_help_bindings_new(_reader_controller)
        bindings = { __default__: :exit_help }
        @dispatcher.register_mode(:help, bindings)
      end

      def register_toc_bindings_new(_reader_controller)
        bindings = {}

        # Exit TOC
        bindings['t'] = :exit_toc
        Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :exit_toc }

        # Navigation
        Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :toc_down }
        Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :toc_up }

        # Selection
        Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :toc_select }

        @dispatcher.register_mode(:toc, bindings)
      end

      def register_bookmarks_bindings_new(_reader_controller)
        bindings = {}

        # Exit bookmarks
        bindings['B'] = :exit_bookmarks
        Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :exit_bookmarks }

        # Navigation
        Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = :bookmark_down }
        Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = :bookmark_up }

        # Actions
        Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = :bookmark_select }
        bindings['d'] = :delete_selected_bookmark

        @dispatcher.register_mode(:bookmarks, bindings)
      end

      def register_annotation_editor_bindings_new(_reader_controller)
        bindings = {}

        # Cancel editor
        bindings["\e"] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.cancel

        # Save: support Ctrl+S (\x13) and 'S'
        bindings["\x13"] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.save
        bindings['S'] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.save

        # Backspace (both variants)
        bindings["\x7F"] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.backspace
        bindings["\b"]   = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.backspace

        # Enter (CR and LF)
        EbookReader::Input::KeyDefinitions::ACTIONS[:confirm].each do |k|
          bindings[k] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.enter
        end

        # Default: insert printable characters
        bindings[:__default__] = EbookReader::Domain::Commands::AnnotationEditorCommandFactory.insert_char

        @dispatcher.register_mode(:annotation_editor, bindings)
      end

      public

      # Switch active bindings according to mode
      def activate_for_mode(mode)
        return unless @dispatcher

        case mode
        when :annotation_editor
          @dispatcher.activate(:annotation_editor)
        when :help
          @dispatcher.activate(:help)
        when :toc
          @dispatcher.activate(:toc)
        when :bookmarks
          @dispatcher.activate(:bookmarks)
        else
          @dispatcher.activate_stack([:read])
        end
      end

      # Removed reader annotations list bindings; annotations are managed via the sidebar
    end
  end
end
