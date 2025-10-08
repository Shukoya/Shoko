# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle settings-related actions in the main menu.
      module SettingsActions
        def toggle_view_mode(_key = nil)
          settings_service.toggle_view_mode
        end

        def toggle_page_numbers(_key = nil)
          settings_service.toggle_page_numbers
        end

        def cycle_line_spacing(_key = nil)
          settings_service.cycle_line_spacing
        end

        def toggle_highlight_quotes(_key = nil)
          settings_service.toggle_highlight_quotes
        end

        def toggle_page_numbering_mode(_key = nil)
          settings_service.toggle_page_numbering_mode
        end

        def wipe_cache(_key = nil)
          message = settings_service.wipe_cache(catalog: @catalog)
          @filtered_epubs = []
          @catalog.scan_message = message if @catalog.respond_to?(:scan_message)
          message
        end

        private

        def settings_service
          @settings_service ||= @dependencies.resolve(:settings_service)
        end
      end
    end
  end
end
