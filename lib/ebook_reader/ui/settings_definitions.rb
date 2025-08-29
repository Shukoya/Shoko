# frozen_string_literal: true

module EbookReader
  module UI
    # A module that defines the structure and content of the settings screen.
    # It provides a list of settings, each with a name, value, and key for
    # user interaction. This module is included in the `SettingsScreen` class.
    module SettingsDefinitions
      def settings_list
        [
          view_mode_setting,
          page_numbers_setting,
          line_spacing_setting,
          highlight_quotes_setting,
          clear_cache_setting,
          page_numbering_mode_setting,
        ]
      end

      private

      def view_mode_setting
        {
          name: 'View Mode',
          value: view_mode_description,
          key: '1',
        }
      end

      def page_numbers_setting
        {
          name: 'Show Page Numbers',
          value: @config.show_page_numbers ? 'Yes' : 'No',
          key: '2',
        }
      end

      def line_spacing_setting
        {
          name: 'Line Spacing',
          value: EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(@config).to_s.capitalize,
          key: '3',
        }
      end

      def highlight_quotes_setting
        {
          name: 'Highlight Quotes',
          value: @config.get([:config, :highlight_quotes]) ? 'Yes' : 'No',
          key: '4',
        }
      end

      def clear_cache_setting
        {
          name: 'Clear Cache',
          value: 'Force rescan of EPUB files',
          key: '5',
          action: true,
        }
      end

      def page_numbering_mode_setting
        {
          name: 'Page Numbering Mode',
          value: EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(@config) == :absolute ? 'Absolute' : 'Dynamic',
          key: '6',
        }
      end

      def view_mode_description
        EbookReader::Domain::Selectors::ConfigSelectors.view_mode(@config) == :split ? 'Duo Page (Side-by-Side)' : 'Single Page (Centered)'
      end
    end
  end
end
