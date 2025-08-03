# frozen_string_literal: true

module EbookReader
  module Core
    # Manages the state of the reader including current position,
    # view settings, and navigation history.
    #
    # This class encapsulates all mutable state for the Reader,
    # making it easier to test and reason about state changes.
    class ReaderState
      # Current chapter index (0-based)
      attr_accessor :current_chapter

      # Current page offset in split view mode
      attr_accessor :left_page, :right_page

      # Current page offset in single view mode
      attr_accessor :single_page

      # Current reader mode (:read, :help, :toc, :bookmarks)
      attr_accessor :mode

      # Selected item in ToC view
      attr_accessor :toc_selected

      # Selected item in bookmarks view
      attr_accessor :bookmark_selected

      # Temporary message to display
      attr_accessor :message

      # Whether the reader is still running
      attr_accessor :running

      # Cached page map for navigation
      attr_accessor :page_map

      # Total pages across all chapters
      attr_accessor :total_pages

      # Current page index for dynamic pagination
      attr_accessor :current_page_index

      # Array storing page count per chapter when in dynamic mode
      attr_accessor :pages_per_chapter

      # Last known terminal dimensions
      attr_accessor :last_width, :last_height

      # Initialize a new reader state
      def initialize
        reset_to_defaults
      end

      # Reset all state to initial values
      def reset_to_defaults
        reset_position_state
        reset_navigation_state
        reset_system_state
      end

      private

      def reset_position_state
        @current_chapter = 0
        @left_page = 0
        @right_page = 0
        @single_page = 0
        @current_page_index = 0
      end

      def reset_navigation_state
        @mode = :read
        @toc_selected = 0
        @bookmark_selected = 0
        @pages_per_chapter = []
      end

      def reset_system_state
        @message = nil
        @running = true
        @page_map = []
        @total_pages = 0
        @last_width = 0
        @last_height = 0
      end

      # Get current page offset based on view mode
      #
      # @param view_mode [Symbol] :split or :single
      # @return [Integer] Current page offset
      def current_page_offset(view_mode)
        view_mode == :split ? @left_page : @single_page
      end

      # Set page offset for all view modes
      #
      # @param offset [Integer] New page offset
      def page_offset=(offset)
        @single_page = offset
        @left_page = offset
        @right_page = offset
      end

      # Check if terminal size changed
      #
      # @param width [Integer] Current width
      # @param height [Integer] Current height
      # @return [Boolean] true if size changed
      def terminal_size_changed?(width, height)
        width != @last_width || height != @last_height
      end

      # Update last known terminal size
      #
      # @param width [Integer] New width
      # @param height [Integer] New height
      def update_terminal_size(width, height)
        @last_width = width
        @last_height = height
      end

      # Create a snapshot of current state for persistence
      #
      # @return [Hash] State snapshot
      def to_h
        {
          current_chapter: @current_chapter,
          page_offset: @single_page,
          mode: @mode,
          timestamp: Time.now.iso8601,
        }
      end

      # Restore state from a snapshot
      #
      # @param snapshot [Hash] State snapshot
      def restore_from(snapshot)
        @current_chapter = snapshot['current_chapter'] || 0
        self.page_offset = snapshot['page_offset'] || 0
        @mode = (snapshot['mode'] || 'read').to_sym
      end

      # Determine if reader is using dynamic page mode
      #
      # @param config [Config] reader configuration
      # @return [Boolean] true if dynamic mode
      def dynamic_page_mode?(config)
        config.page_numbering_mode == :dynamic
      end

      public :current_page_offset,
             :page_offset=,
             :terminal_size_changed?,
             :update_terminal_size,
             :to_h,
             :restore_from,
             :dynamic_page_mode?
    end
  end
end
