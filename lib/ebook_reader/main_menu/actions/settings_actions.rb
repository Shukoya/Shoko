# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle settings-related actions in the main menu.
      module SettingsActions
        def handle_setting_change(key)
          @input_handler.handle_setting_change(key)
        end

        def toggle_view_mode
          @config.view_mode = @config.view_mode == :split ? :single : :split
          @config.save
        end

        def toggle_page_numbers
          @config.show_page_numbers = !@config.show_page_numbers
          @config.save
        end

        def cycle_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@config.line_spacing) || 1
          @config.line_spacing = modes[(current + 1) % 3]
          @config.save
        end

        def toggle_highlight_quotes
          @config.highlight_quotes = !@config.highlight_quotes
          @config.save
        end

        def toggle_page_numbering_mode
          @config.page_numbering_mode = @config.page_numbering_mode == :absolute ? :dynamic : :absolute
          @config.save
        end

        def clear_cache
          EPUBFinder.clear_cache
          @scanner.epubs = []
          @filtered_epubs = []
          @scanner.scan_status = :idle
          @scanner.scan_message = "Cache cleared! Use 'Find Book' to rescan"
        end
      end
    end
  end
end
