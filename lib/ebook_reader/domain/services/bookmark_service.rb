# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Pure business logic for bookmark management.
      # Replaces the tightly coupled BookmarkService with clean domain logic.
      class BookmarkService < BaseService
        protected

        def required_dependencies
          %i[state_store event_bus]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @event_bus = resolve(:event_bus)
          @persistence = resolve(:bookmark_persistence) if registered?(:bookmark_persistence)
          @setup_service_dependencies ||= DefaultBookmarkPersistence.new
        end

        # Add bookmark at current position
        #
        # @param text_snippet [String] Optional text snippet for the bookmark
        # @return [Bookmark] Created bookmark
        def add_bookmark(text_snippet = nil)
          current_state = @state_store.current_state

          bookmark = create_bookmark_from_state(current_state, text_snippet)
          save_bookmark(bookmark)

          @event_bus.emit_event(:bookmark_added, { bookmark: bookmark })
          bookmark
        end

        # Remove bookmark
        #
        # @param bookmark [Bookmark] Bookmark to remove
        def remove_bookmark(bookmark)
          @persistence.delete_bookmark(current_book_path, bookmark)
          refresh_bookmarks

          @event_bus.emit_event(:bookmark_removed, { bookmark: bookmark })
        end

        # Get all bookmarks for current book
        #
        # @return [Array<Bookmark>] Array of bookmarks
        def get_bookmarks
          book_path = current_book_path
          return [] unless book_path

          @persistence.load_bookmarks(book_path)
        end

        # Navigate to bookmark
        #
        # @param bookmark [Bookmark] Bookmark to navigate to
        def jump_to_bookmark(bookmark)
          @state_store.update({
                                %i[reader current_chapter] => bookmark.chapter_index,
                                %i[reader current_page] => bookmark.page_offset,
                              })

          @event_bus.emit_event(:navigated_to_bookmark, { bookmark: bookmark })
        end

        # Check if current position has bookmark
        #
        # @return [Boolean]
        def current_position_bookmarked?
          current_state = @state_store.current_state
          bookmarks = get_bookmarks

          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          current_page = current_state.dig(:reader, :current_page) || 0

          bookmarks.any? do |bookmark|
            bookmark.chapter_index == current_chapter &&
              bookmark.page_offset == current_page
          end
        end

        # Get bookmark at current position (if any)
        #
        # @return [Bookmark, nil]
        def bookmark_at_current_position
          current_state = @state_store.current_state
          bookmarks = get_bookmarks

          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          current_page = current_state.dig(:reader, :current_page) || 0

          bookmarks.find do |bookmark|
            bookmark.chapter_index == current_chapter &&
              bookmark.page_offset == current_page
          end
        end

        # Toggle bookmark at current position
        #
        # @param text_snippet [String] Text snippet if adding
        # @return [Symbol] :added or :removed
        def toggle_bookmark(text_snippet = nil)
          existing_bookmark = bookmark_at_current_position

          if existing_bookmark
            remove_bookmark(existing_bookmark)
            :removed
          else
            add_bookmark(text_snippet)
            :added
          end
        end

        private

        def create_bookmark_from_state(state, text_snippet)
          Models::Bookmark.new(
            chapter_index: state.dig(:reader, :current_chapter) || 0,
            page_offset: state.dig(:reader, :current_page) || 0,
            text_snippet: text_snippet || generate_text_snippet(state),
            created_at: Time.now
          )
        end

        def generate_text_snippet(state)
          # This would be implemented based on the current document content
          # For now, return a placeholder
          chapter_index = state.dig(:reader, :current_chapter) || 0
          page_offset = state.dig(:reader, :current_page) || 0
          "Chapter #{chapter_index + 1}, Page #{page_offset + 1}"
        end

        def current_book_path
          @state_store.get(%i[reader book_path])
        end

        def save_bookmark(bookmark)
          book_path = current_book_path
          return unless book_path

          @persistence.save_bookmark(book_path, bookmark)
          refresh_bookmarks
        end

        def refresh_bookmarks
          bookmarks = get_bookmarks
          @state_store.set(%i[reader bookmarks], bookmarks)
        end
      end

      # Default persistence implementation using the existing BookmarkManager
      class DefaultBookmarkPersistence
        def load_bookmarks(book_path)
          EbookReader::BookmarkManager.get(book_path)
        end

        def save_bookmark(book_path, bookmark)
          EbookReader::BookmarkManager.add(book_path, bookmark)
        end

        def delete_bookmark(book_path, bookmark)
          EbookReader::BookmarkManager.delete(book_path, bookmark)
        end
      end
    end
  end
end
