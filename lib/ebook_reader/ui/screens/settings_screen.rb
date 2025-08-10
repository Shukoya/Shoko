# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../components/surface'
require_relative '../../components/rect'

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
        include EbookReader::Constants

        def initialize(config, scanner, _renderer = nil)
          @config = config
          @scanner = scanner
          @renderer = nil
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          surface.write(bounds, 1, 2, "#{UIConstants::COLOR_TEXT_ACCENT}⚙️  Settings#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [width - 20, 60].max,
                        "#{UIConstants::COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}")

          start_row = 5
          build_settings_list.each_with_index do |setting, i|
            row_base = start_row + (i * 3)
            break if row_base >= height - 4

            surface.write(bounds, row_base, 4,
                          UIConstants::COLOR_TEXT_WARNING + "[#{setting[:key]}]" + UIConstants::COLOR_TEXT_PRIMARY + " #{setting[:name]}" + Terminal::ANSI::RESET)
            next unless row_base + 1 < height - 3

            color = setting[:action] ? UIConstants::COLOR_TEXT_ACCENT : UIConstants::SELECTION_HIGHLIGHT
            surface.write(bounds, row_base + 1, 8, color + setting[:value].to_s + Terminal::ANSI::RESET)
          end

          status = @scanner.scan_message if @scanner.scan_message && @scanner.scan_status == :idle
          if status && !status.empty?
            row = 5 + (build_settings_list.length * 3) + 1
            surface.write(bounds, row, 4, UIConstants::COLOR_TEXT_WARNING + status + Terminal::ANSI::RESET)
          end

          surface.write(bounds, height - 3, 4,
                        "#{UIConstants::COLOR_TEXT_DIM}Press number keys to toggle settings#{Terminal::ANSI::RESET}")
          surface.write(bounds, height - 2, 4,
                        "#{UIConstants::COLOR_TEXT_DIM}Changes are saved automatically#{Terminal::ANSI::RESET}")
        end

        private

        def build_settings_list
          settings_list
        end

        # Rendering delegated to MainMenuRenderer
      end
    end
  end
end
