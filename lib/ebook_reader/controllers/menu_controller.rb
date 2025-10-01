# frozen_string_literal: true

require_relative '../mouseable_reader'
require_relative '../main_menu/actions/file_actions'
require_relative '../main_menu/actions/settings_actions'
require_relative '../input/dispatcher'
require_relative '../components/main_menu_component'
require_relative '../components/surface'
require_relative '../components/rect'
require_relative '../application/frame_coordinator'
require_relative '../main_menu/menu_progress_presenter'
require_relative 'menu/state_controller'
require_relative 'menu/input_controller'
require_relative 'menu/ui_controller'

module EbookReader
  module Controllers
    # Controller responsible for the menu orchestration loop.
    class MenuController
      include EbookReader::MainMenu::Actions::FileActions
      include EbookReader::MainMenu::Actions::SettingsActions
      include Input::KeyDefinitions::Helpers

      attr_accessor :filtered_epubs
      attr_reader :state, :main_menu_component, :catalog, :dependencies,
                  :terminal_service, :frame_coordinator, :render_pipeline,
                  :state_controller, :input_controller, :ui_controller

      def scanner
        @catalog
      end

      def config
        @state
      end

      def initialize(dependencies = nil)
        @dependencies = dependencies || Domain::ContainerFactory.create_default_container
        setup_state
        setup_services
        setup_components
        @state_controller = Menu::StateController.new(self)
        @input_controller = Menu::InputController.new(self)
        @dispatcher = @input_controller.dispatcher
        @ui_controller = Menu::UIController.new(self, @state_controller)
      end

      def run
        @terminal_service.setup
        @catalog.load_cached
        epubs = @catalog.entries || []
        @filtered_epubs = epubs
        @main_menu_component.browse_screen.filtered_epubs = epubs
        @catalog.start_scan if epubs.empty?

        main_loop
      rescue Interrupt
        cleanup_and_exit(0, "\nGoodbye!")
      rescue StandardError => e
        cleanup_and_exit(1, "Error: #{e.message}", e)
      ensure
        @catalog.cleanup if @catalog.respond_to?(:cleanup)
      end

      def handle_menu_selection
        ui_controller.handle_menu_selection
      end

      def handle_navigation(direction)
        ui_controller.handle_navigation(direction)
      end

      def switch_to_browse
        ui_controller.switch_to_browse
      end

      def switch_to_search
        ui_controller.switch_to_search
      end

      def switch_to_mode(mode)
        ui_controller.switch_to_mode(mode)
      end

      def open_file_dialog
        ui_controller.open_file_dialog
      end

      def cleanup_and_exit(code, message, error = nil)
        ui_controller.cleanup_and_exit(code, message, error)
      end

      def handle_browse_navigation(key)
        ui_controller.handle_browse_navigation(key)
      end

      def handle_backspace_input
        ui_controller.handle_backspace_input
      end

      def handle_character_input(key)
        ui_controller.handle_character_input(key)
      end

      def switch_to_edit_annotation(annotation, book_path)
        ui_controller.switch_to_edit_annotation(annotation, book_path)
      end

      def refresh_scan(force: true)
        state_controller.refresh_scan(force: force)
      end

      def handle_selection
        ui_controller.handle_selection
      end

      def handle_cancel
        ui_controller.handle_cancel
      end

      def exit_current_mode
        ui_controller.exit_current_mode
      end

      def delete_selected_item
        ui_controller.delete_selected_item
      end

      # Settings are handled directly via dispatcher bindings

      private

      def setup_state
        @state = @dependencies.resolve(:global_state)
        @filtered_epubs = []
      end

      def setup_services
        # Use dependency injection for services
        @catalog = @dependencies.resolve(:catalog_service)
        @terminal_service = @dependencies.resolve(:terminal_service)
        @frame_coordinator = Application::FrameCoordinator.new(@dependencies)
        @render_pipeline = Application::RenderPipeline.new(@dependencies)
        @scanner = @catalog
      end

      def setup_components
        @main_menu_component = Components::MainMenuComponent.new(self, @dependencies)
      end

      public

      # Library mode helpers
      def library_up
        ui_controller.library_up
      end

      def library_down
        ui_controller.library_down
      end

      def library_select
        ui_controller.library_select
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
        input_controller.handle_keys(keys)
      end

      def read_input_keys
        @terminal_service.read_keys_blocking(limit: 10)
      end

      def process_scan_results_if_available
        return unless (epubs = @catalog.process_results)

        @catalog.update_entries(epubs) if epubs
        @filtered_epubs = epubs
        @main_menu_component.browse_screen.filtered_epubs = epubs
        @main_menu_component.library_screen.invalidate_cache!
      end

      def draw_screen
        @frame_coordinator.with_frame do |surface, bounds, _w, _h|
          @render_pipeline.render_component(surface, bounds, @main_menu_component)
        end
      end

      # Annotation helpers (public so dispatcher can invoke explicitly)
      def open_selected_annotation
        state_controller.open_selected_annotation
      end

      def open_selected_annotation_for_edit
        state_controller.open_selected_annotation_for_edit
      end

      def delete_selected_annotation
        state_controller.delete_selected_annotation
      end

      def save_current_annotation_edit
        state_controller.save_current_annotation_edit
      end

      private

      # Provide current editor component for domain commands in menu context
      def current_editor_component
        return nil unless EbookReader::Domain::Selectors::MenuSelectors.mode(@state) == :annotation_editor

        @main_menu_component&.annotation_edit_screen
      end

      # file_not_found and handle_reader_error provided by Actions::FileActions

      # Use Actions::FileActions#sanitize_input_path and #handle_file_path

      def load_recent_books
        recent_repository = begin
          @dependencies.resolve(:recent_library_repository)
        rescue StandardError
          nil
        end
        recent_repository ? recent_repository.all : []
      end

      def handle_dialog_error(error)
        Infrastructure::Logger.error('Dialog error', error: error.message)
        @catalog.scan_message = "Error: #{error.message}"
        @catalog.scan_status = :error
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
end
