# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle settings-related actions in the main menu.
      module SettingsActions
        def toggle_view_mode
          current_mode = @state.get(%i[config view_mode]) || :split
          new_mode = current_mode == :split ? :single : :split
          @state.set(%i[config view_mode], new_mode)
          @state.save_config
        end

        def toggle_page_numbers
          current = @state.get(%i[config show_page_numbers])
          @state.set(%i[config show_page_numbers], !current)
          @state.save_config
        end

        def cycle_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@state.get(%i[config line_spacing])) || 1
          @state.set(%i[config line_spacing], modes[(current + 1) % 3])
          @state.save_config
        end

        def toggle_highlight_quotes
          current = @state.get(%i[config highlight_quotes])
          @state.set(%i[config highlight_quotes], !current)
          @state.save_config
        end

        def toggle_page_numbering_mode
          current = @state.get(%i[config page_numbering_mode])
          @state.set(%i[config page_numbering_mode], current == :absolute ? :dynamic : :absolute)
          @state.save_config
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
