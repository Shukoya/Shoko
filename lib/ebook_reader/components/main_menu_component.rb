# frozen_string_literal: true

require_relative 'base_component'
require_relative 'layouts/vertical'
require_relative 'screens/menu_screen_component'
require_relative 'screens/browse_screen_component'
require_relative 'screens/library_screen_component'
require_relative 'screens/settings_screen_component'
require_relative 'screens/open_file_screen_component'
require_relative 'screens/annotations_screen_component'
require_relative 'screens/annotation_edit_screen_component'

module EbookReader
  module Components
    # Root component for the main menu system
    class MainMenuComponent < BaseComponent
      def initialize(main_menu, dependencies)
        super()
        @main_menu = main_menu
        @state = main_menu.state
        @dependencies = dependencies
        @scanner = @main_menu.scanner

        setup_screen_components

        # Initialize current screen
        @current_screen = @screen_components[:menu]

        # Observe mode changes to switch active component
        @state.add_observer(self, %i[menu mode], %i[menu selected])
      end

      def state_changed(path, _old_value, new_value)
        return unless path == %i[menu mode]

        mapped = new_value == :search ? :browse : new_value
        @current_screen = @screen_components[mapped] || @screen_components[:menu]
      end

      def do_render(surface, bounds)
        current_screen&.render(surface, bounds)
      end

      def preferred_height(_available_height)
        :fill
      end

      attr_reader :current_screen

      # Delegate screen-specific methods
      def browse_screen
        @screen_components[:browse]
      end

      # recent screen removed

      def settings_screen
        @screen_components[:settings]
      end

      def open_file_screen
        @screen_components[:open_file]
      end

      def annotations_screen
        @screen_components[:annotations]
      end

      def annotation_detail_screen
        @screen_components[:annotation_detail]
      end

      private

      def setup_screen_components
        @screen_components = {
          menu: Screens::MenuScreenComponent.new(@state),
          browse: Screens::BrowseScreenComponent.new(@scanner, @state),
          library: Screens::LibraryScreenComponent.new(@state, @dependencies),
          settings: Screens::SettingsScreenComponent.new(@state, @scanner),
          open_file: Screens::OpenFileScreenComponent.new(@state),
          annotations: Screens::AnnotationsScreenComponent.new(@state),
          annotation_editor: Screens::AnnotationEditScreenComponent.new(@state, @dependencies),
          annotation_detail: Screens::AnnotationDetailScreenComponent.new(@state),
        }
      end

      public

      def annotation_edit_screen
        @screen_components[:annotation_editor]
      end
    end
  end
end
