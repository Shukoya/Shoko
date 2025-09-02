# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/bookmark_events'

module EbookReader
  module Domain
    module Services
      # Pure business logic for bookmark management.
      # Replaces the tightly coupled BookmarkService with clean domain logic.
      class BookmarkService < BaseService
        # Add bookmark at current position
        #
        # @param text_snippet [String] Optional text snippet for the bookmark
        # @return [Bookmark] Created bookmark
        def add_bookmark(text_snippet = nil)
          current_state = @state_store.current_state
          book_path = current_book_path
          return nil unless book_path

          chapter_index = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)

          bookmark = @bookmark_repository.add_for_book(
            book_path,
            chapter_index: chapter_index,
            line_offset: line_offset,
            text_snippet: text_snippet || generate_text_snippet(current_state)
          )

          refresh_bookmarks
          
          # Publish domain event
          @domain_event_bus.publish(Events::BookmarkAdded.new(
            book_path: book_path,
            bookmark: bookmark
          ))
          
          # Legacy event bus for backward compatibility
          @event_bus.emit_event(:bookmark_added, { bookmark: bookmark })
          bookmark
        end

        # Remove bookmark
        #
        # @param bookmark [Bookmark] Bookmark to remove
        def remove_bookmark(bookmark)
          book_path = current_book_path
          return unless book_path

          @bookmark_repository.delete_for_book(book_path, bookmark)
          refresh_bookmarks

          # Publish domain event
          @domain_event_bus.publish(Events::BookmarkRemoved.new(
            book_path: book_path,
            bookmark: bookmark
          ))
          
          # Legacy event bus for backward compatibility
          @event_bus.emit_event(:bookmark_removed, { bookmark: bookmark })
        end

        # Get all bookmarks for current book
        #
        # @return [Array<Bookmark>] Array of bookmarks
        def get_bookmarks
          book_path = current_book_path
          return [] unless book_path

          @bookmark_repository.find_by_book_path(book_path)
        end

        # Navigate to bookmark
        #
        # @param bookmark [Bookmark] Bookmark to navigate to
        def jump_to_bookmark(bookmark)
          @state_store.update({
                                %i[reader current_chapter] => bookmark.chapter_index,
                                %i[reader current_page] => bookmark.page_offset,
                              })

          # Publish domain event
          @domain_event_bus.publish(Events::BookmarkNavigated.new(
            book_path: current_book_path,
            bookmark: bookmark
          ))
          
          # Legacy event bus for backward compatibility
          @event_bus.emit_event(:navigated_to_bookmark, { bookmark: bookmark })
        end

        # Check if current position has bookmark
        #
        # @return [Boolean]
        def current_position_bookmarked?
          current_state = @state_store.current_state
          book_path = current_book_path
          return false unless book_path

          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)

          @bookmark_repository.exists_at_position?(book_path, current_chapter, line_offset)
        end

        # Get bookmark at current position (if any)
        #
        # @return [Bookmark, nil]
        def bookmark_at_current_position
          current_state = @state_store.current_state
          book_path = current_book_path
          return nil unless book_path

          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)

          @bookmark_repository.find_at_position(book_path, current_chapter, line_offset)
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

        protected

        def required_dependencies
          %i[state_store event_bus bookmark_repository domain_event_bus]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @event_bus = resolve(:event_bus)
          @bookmark_repository = resolve(:bookmark_repository)
          @domain_event_bus = resolve(:domain_event_bus)
        end

        private

        def get_current_line_offset(state)
          # Get the current line position depending on view mode
          view_mode = state.dig(:config, :view_mode) || :split
          if view_mode == :split
            state.dig(:reader, :left_page) || 0
          else
            state.dig(:reader, :single_page) || 0
          end
        end

        def generate_text_snippet(state)
          # This would be implemented based on the current document content
          # For now, return a placeholder
          chapter_index = state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(state)
          "Chapter #{chapter_index + 1}, Line #{line_offset + 1}"
        end

        def current_book_path
          @state_store.get(%i[reader book_path])
        end

        def refresh_bookmarks
          bookmarks = get_bookmarks
          @state_store.update({ %i[reader bookmarks] => bookmarks })
        end
      end
    end
  end
end
