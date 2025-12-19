# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Factory methods for creating common state actions
      # Provides a clean API for dispatching state changes throughout the app
      module ActionCreators
        # Reader mode actions
        def self.switch_to_read_mode
          UpdateReaderModeAction.new(:read)
        end

        def self.switch_to_help_mode
          UpdateReaderModeAction.new(:help)
        end

        def self.switch_to_toc_mode
          UpdateReaderModeAction.new(:toc)
        end

        def self.switch_to_bookmarks_mode
          UpdateReaderModeAction.new(:bookmarks)
        end

        def self.switch_to_annotations_mode
          UpdateReaderModeAction.new(:annotations)
        end

        # Page navigation actions
        def self.go_to_page(page_index)
          UpdatePageAction.new(current_page_index: page_index)
        end

        def self.update_split_pages(left_page, right_page)
          UpdatePageAction.new(left_page: left_page, right_page: right_page)
        end

        def self.update_single_page(page)
          UpdatePageAction.new(single_page: page)
        end

        # Chapter navigation actions
        def self.go_to_chapter(chapter_index)
          UpdateChapterAction.new(chapter_index)
        end

        # Selection actions
        def self.update_selection(selection_data)
          UpdateSelectionAction.new(selection_data)
        end

        def self.clear_selection
          ClearSelectionAction.new
        end

        # Message actions
        def self.show_message(message)
          UpdateMessageAction.new(message)
        end

        def self.clear_message
          ClearMessageAction.new
        end

        # Configuration actions
        def self.toggle_view_mode
          ToggleViewModeAction.new
        end

        def self.switch_reader_mode(mode)
          SwitchReaderModeAction.new(mode)
        end

        def self.update_view_mode(mode)
          UpdateConfigAction.new(view_mode: mode)
        end

        def self.update_line_spacing(spacing)
          UpdateConfigAction.new(line_spacing: spacing)
        end

        def self.update_theme(theme)
          UpdateConfigAction.new(theme: theme)
        end

        def self.toggle_page_numbers(state)
          current = EbookReader::Domain::Selectors::ConfigSelectors.show_page_numbers(state)
          UpdateConfigAction.new(show_page_numbers: !current)
        end

        # Bookmark actions
        def self.update_bookmarks(bookmarks)
          UpdateBookmarksAction.new(bookmarks)
        end
      end
    end
  end
end
