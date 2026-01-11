# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module Commands
      # Application-level commands for mode switching and system control.
      class ApplicationCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "app_#{action}",
            description: description || "Application #{action.to_s.tr('_', ' ')}"
          )
        end

        protected

        def perform(context, _params = {})
          deps = dependencies_from(context)

          case @action
          when :quit_to_menu
            handle_quit_to_menu(deps)
          when :quit_application
            handle_quit_application(deps)
          when :toggle_view_mode
            handle_toggle_view_mode(deps)
          when :show_help
            handle_show_help(deps)
          when :show_toc
            handle_show_toc(deps)
          when :show_bookmarks
            handle_show_bookmarks(deps)
          when :show_annotations
            handle_show_annotations(deps)
          else
            raise ExecutionError.new("Unknown application action: #{@action}", command_name: name)
          end

          @action
        end

        private

        def handle_quit_to_menu(deps)
          controller = resolve_optional(deps, :state_controller)
          if controller.respond_to?(:quit_to_menu)
            controller.quit_to_menu
          else
            dispatch_action(deps, Application::Actions::QuitToMenuAction.new)
          end
        end

        def handle_quit_application(deps)
          controller = resolve_optional(deps, :state_controller)
          if controller.respond_to?(:quit_application)
            controller.quit_application
            return
          end

          handle_quit_to_menu(deps)
          force_cleanup(deps)
          Kernel.exit(0)
        end

        def handle_toggle_view_mode(deps)
          controller = resolve_optional(deps, :ui_controller)
          if controller.respond_to?(:toggle_view_mode)
            controller.toggle_view_mode
          else
            dispatch_action(deps, Application::Actions::ToggleViewModeAction.new)
          end
        end

        def handle_show_help(deps)
          controller = resolve_optional(deps, :ui_controller)
          if controller.respond_to?(:show_help)
            controller.show_help
          else
            state_store = resolve_state_store(deps)
            state_store&.set(%i[reader mode], :help)
          end
        end

        def handle_show_toc(deps)
          controller = resolve_optional(deps, :ui_controller)
          return unless controller.respond_to?(:open_toc)

          controller.open_toc
        end

        def handle_show_bookmarks(deps)
          controller = resolve_optional(deps, :ui_controller)
          return unless controller.respond_to?(:open_bookmarks)

          controller.open_bookmarks
        end

        def handle_show_annotations(deps)
          controller = resolve_optional(deps, :ui_controller)
          return unless controller.respond_to?(:open_annotations)

          controller.open_annotations
        end

        def dependencies_from(context)
          return context.dependencies if context.respond_to?(:dependencies)

          raise ExecutionError.new('Command context must expose dependencies', command_name: name)
        end

        def resolve_optional(deps, key)
          return nil if deps.respond_to?(:registered?) && !deps.registered?(key)

          deps.resolve(key)
        rescue StandardError
          nil
        end

        def resolve_state_store(deps)
          resolve_optional(deps, :state_store) || resolve_optional(deps, :global_state)
        end

        def dispatch_action(deps, action)
          state_store = resolve_state_store(deps)
          state_store&.dispatch(action)
        end

        def force_cleanup(deps)
          terminal = resolve_optional(deps, :terminal_service)
          return unless terminal

          if terminal.respond_to?(:force_cleanup)
            terminal.force_cleanup
          elsif terminal.respond_to?(:cleanup)
            terminal.cleanup
          end
        end
      end

      # Command that switches the reader into a specific UI mode.
      class ModeCommand < BaseCommand
        def initialize(mode, name: nil, description: nil)
          @mode = mode
          super(
            name: name || "mode_#{mode}",
            description: description || "Switch to #{mode} mode"
          )
        end

        def validate_parameters(params)
          super

          valid_modes = %i[read help search]
          return if valid_modes.include?(@mode)

          raise ValidationError.new("Mode must be one of #{valid_modes}", command_name: name)
        end

        protected

        def perform(context, _params = {})
          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader mode], @mode)

          @mode
        end
      end

      # Factory methods for common application commands
      module ApplicationCommandFactory
        def self.quit_to_menu
          ApplicationCommand.new(:quit_to_menu)
        end

        def self.quit_application
          ApplicationCommand.new(:quit_application)
        end

        def self.toggle_view_mode
          ApplicationCommand.new(:toggle_view_mode)
        end

        def self.show_help
          ApplicationCommand.new(:show_help)
        end

        def self.show_toc
          ApplicationCommand.new(:show_toc)
        end

        def self.show_bookmarks
          ApplicationCommand.new(:show_bookmarks)
        end

        def self.show_annotations
          ApplicationCommand.new(:show_annotations)
        end

        def self.switch_to_mode(mode)
          ModeCommand.new(mode)
        end
      end
    end
  end
end
