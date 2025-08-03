# frozen_string_literal: true

module EbookReader
  module UI
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
          value: @config.line_spacing.to_s.capitalize,
          key: '3',
        }
      end

      def highlight_quotes_setting
        {
          name: 'Highlight Quotes',
          value: @config.highlight_quotes ? 'Yes' : 'No',
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
          value: @config.page_numbering_mode == :absolute ? 'Absolute' : 'Dynamic',
          key: '6',
        }
      end

      def view_mode_description
        @config.view_mode == :split ? 'Split View (Two Pages)' : 'Single Page (Centered)'
      end
    end
  end
end
