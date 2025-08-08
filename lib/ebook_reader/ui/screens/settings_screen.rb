# frozen_string_literal: true

module EbookReader
  module UI
    # A collection of UI screens that make up the application interface.
    # Each screen is responsible for rendering a specific part of the UI,
    # such as the main menu, the book browser, or the settings page.
    module Screens
      # Presents application settings and allows users to toggle
      # various configuration options.
      require_relative '../settings_definitions'

      # Renders the settings screen, allowing users to view and modify application
      # configuration. It uses the `SettingsDefinitions` module to build the list
      # of available settings and their current values.
      class SettingsScreen
        include UI::SettingsDefinitions

        def initialize(config, scanner, renderer = nil)
          @config = config
          @scanner = scanner
          @renderer = renderer
        end

        def draw(height, width)
          items = build_settings_list.map do |s|
            UI::MainMenuRenderer::SettingsItem.new(s[:key], s[:name], s[:value], s[:action])
          end
          status = @scanner.scan_message if @scanner.scan_message && @scanner.scan_status == :idle
          renderer.render_settings_screen(
            UI::MainMenuRenderer::SettingsContext.new(
              height: height, width: width, items: items, status_message: status
            )
          )
        end

        private

        def renderer
          @renderer ||= UI::MainMenuRenderer.new(@config)
        end

        def build_settings_list
          settings_list
        end

        # Rendering delegated to MainMenuRenderer
      end
    end
  end
end
