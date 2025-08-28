# frozen_string_literal: true

module EbookReader
  module Domain
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
          case @action
          when :quit_to_menu
            handle_quit_to_menu(context)
          when :quit_application
            handle_quit_application(context)
          when :toggle_view_mode
            handle_toggle_view_mode(context)
          when :show_help
            handle_show_help(context)
          when :show_toc
            handle_show_toc(context)
          when :show_bookmarks
            handle_show_bookmarks(context)
          else
            raise ExecutionError.new("Unknown application action: #{@action}", command_name: name)
          end

          @action
        end

        private

        def handle_quit_to_menu(context)
          state_store = context.dependencies.resolve(:state_store)

          # Save progress before quitting
          save_progress(context)

          # Set running flag to false
          state_store.set(%i[reader running], false)
        end

        def handle_quit_application(context)
          save_progress(context)

          # Clean shutdown
          context.cleanup if context.respond_to?(:cleanup)

          exit(0)
        end

        def handle_toggle_view_mode(context)
          state_store = context.dependencies.resolve(:state_store)
          current_state = state_store.current_state

          current_mode = current_state.dig(:reader, :view_mode) || :split
          new_mode = current_mode == :split ? :single : :split

          state_store.update({
                               %i[reader view_mode] => new_mode,
                               %i[ui needs_redraw] => true,
                             })

          # Clear page cache since layout changed
          return unless context.dependencies.registered?(:page_calculator)

          page_calculator = context.dependencies.resolve(:page_calculator)
          page_calculator.clear_cache if page_calculator.respond_to?(:clear_cache)
        end

        def handle_show_help(context)
          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader mode], :help)
        end

        def handle_show_toc(context)
          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader mode], :toc)
        end

        def handle_show_bookmarks(context)
          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader mode], :bookmarks)
        end

        def save_progress(context)
          # This would integrate with a progress persistence service
          return unless context.dependencies.registered?(:progress_service)

          progress_service = context.dependencies.resolve(:progress_service)
          return unless progress_service.respond_to?(:save_current_progress)

          progress_service.save_current_progress
        end
      end

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

          valid_modes = %i[read help toc bookmarks search]
          return if valid_modes.include?(@mode)

          raise ValidationError.new("Mode must be one of #{valid_modes}", command_name: name)
        end

        protected

        def perform(context, _params = {})
          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader mode], @mode)

          # Mode-specific initialization
          case @mode
          when :toc
            # Load table of contents if not already loaded
            load_toc_if_needed(context)
          when :bookmarks
            # Refresh bookmarks
            refresh_bookmarks(context)
          end

          @mode
        end

        private

        def load_toc_if_needed(context)
          # This would integrate with document service to load TOC
          # For now, just mark that TOC is needed
          state_store = context.dependencies.resolve(:state_store)
          current_state = state_store.current_state

          return if current_state.dig(:reader, :toc_loaded)

          state_store.set(%i[reader toc_loaded], true)
        end

        def refresh_bookmarks(context)
          return unless context.dependencies.registered?(:bookmark_service)

          bookmark_service = context.dependencies.resolve(:bookmark_service)
          bookmarks = bookmark_service.get_bookmarks

          state_store = context.dependencies.resolve(:state_store)
          state_store.set(%i[reader bookmarks], bookmarks)
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

        def self.switch_to_mode(mode)
          ModeCommand.new(mode)
        end
      end
    end
  end
end
