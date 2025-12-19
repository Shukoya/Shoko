# frozen_string_literal: true

require_relative 'key_definitions'
require_relative 'command_builders/navigation_builder'
require_relative 'command_builders/exit_builder'
require_relative 'command_builders/menu_selection_builder'
require_relative 'command_builders/reader_navigation_builder'
require_relative 'command_builders/reader_control_builder'
require_relative 'command_builders/text_input_builder'
require_relative 'command_builders/bookmark_builder'
require_relative 'command_builders/helpers'

module EbookReader
  module Input
    # Factory for creating common input command patterns
    module CommandFactory
      # Builders for list-like up/down navigation commands.
      module Navigation
        module_function

        def list(selection_field:, max_value_proc:)
          CommandBuilders::NavigationBuilder.new(selection_field: selection_field,
                                                 max_value_proc: max_value_proc).build
        end

        def reader
          CommandBuilders::ReaderNavigationBuilder.new.build
        end
      end

      # Builders for high-level reader control commands (toggles, exit actions).
      module Control
        module_function

        def reader
          CommandBuilders::ReaderControlBuilder.new.build
        end

        def exit(exit_action)
          CommandBuilders::ExitBuilder.new(exit_action).build
        end
      end

      # Builders for menu selection commands.
      module Menu
        module_function

        def selection
          CommandBuilders::MenuSelectionBuilder.new.build
        end
      end

      # Builders for editable text input command maps.
      module TextInput
        module_function

        def commands(input_field, context_method: nil, cursor_field: nil)
          CommandBuilders::TextInputBuilder.new(input_field: input_field,
                                                context_method: context_method,
                                                cursor_field: cursor_field).build
        end
      end

      # Builders for bookmark-mode command maps.
      module Bookmarks
        module_function

        def list(empty_handler = nil)
          CommandBuilders::BookmarkBuilder.new(empty_handler).build
        end
      end

      module_function

      def navigation_commands(_context, selection_field, max_value_proc)
        Navigation.list(selection_field: selection_field, max_value_proc: max_value_proc)
      end

      def exit_commands(exit_action)
        Control.exit(exit_action)
      end

      def menu_selection_commands
        Menu.selection
      end

      def reader_navigation_commands
        Navigation.reader
      end

      def reader_control_commands
        Control.reader
      end

      def text_input_commands(input_field, context_method = nil, cursor_field: nil)
        TextInput.commands(input_field, context_method: context_method, cursor_field: cursor_field)
      end

      def bookmark_commands(empty_handler = nil)
        Bookmarks.list(empty_handler)
      end
    end
  end
end
