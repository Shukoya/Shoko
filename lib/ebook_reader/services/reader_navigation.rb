# frozen_string_literal: true

module EbookReader
  module Services
    # Handles all navigation logic for the reader.
    # Extracted from Reader class to separate concerns and improve testability.
    class ReaderNavigation
      # Initialize navigation service
      #
      # @param state [Core::ReaderState] Reader state
      # @param document [EPUBDocument] Current document
      # @param config [Config] Reader configuration
      def initialize(state, document, config)
        @state = state
        @document = document
        @config = config
      end

      # Scroll down by one line
      #
      # @param max_page [Integer] Maximum page number
      def scroll_down(max_page)
        if @config.view_mode == :split
          @state.left_page = [@state.left_page + 1, max_page].min
          @state.right_page = [@state.right_page + 1, max_page].min
        else
          @state.single_page = [@state.single_page + 1, max_page].min
        end
      end

      # Scroll up by one line
      def scroll_up
        if @config.view_mode == :split
          @state.left_page = [@state.left_page - 1, 0].max
          @state.right_page = [@state.right_page - 1, 0].max
        else
          @state.single_page = [@state.single_page - 1, 0].max
        end
      end

      # Navigate to next page
      #
      # @param content_height [Integer] Lines per page
      # @param max_page [Integer] Maximum page offset
      def next_page(content_height, max_page)
        if @config.view_mode == :split
          next_page_split_view(content_height, max_page)
        else
          next_page_single_view(content_height, max_page)
        end
      end

      def next_page_split_view(content_height, max_page)
        if @state.right_page < max_page
          @state.left_page = @state.right_page
          @state.right_page = [@state.right_page + content_height, max_page].min
        elsif can_go_to_next_chapter?
          go_to_next_chapter
        end
      end

      def next_page_single_view(content_height, max_page)
        if @state.single_page < max_page
          @state.single_page = [@state.single_page + content_height, max_page].min
        elsif can_go_to_next_chapter?
          go_to_next_chapter
        end
      end

      # Navigate to previous page
      #
      # @param content_height [Integer] Lines per page
      def previous_page(content_height)
        if @config.view_mode == :split
          previous_page_split_view(content_height)
        else
          previous_page_single_view(content_height)
        end
      end

      def previous_page_split_view(content_height)
        if @state.left_page.positive?
          @state.right_page = @state.left_page
          @state.left_page = [@state.left_page - content_height, 0].max
        elsif can_go_to_previous_chapter?
          go_to_previous_chapter_end
        end
      end

      def previous_page_single_view(content_height)
        if @state.single_page.positive?
          @state.single_page = [@state.single_page - content_height, 0].max
        elsif can_go_to_previous_chapter?
          go_to_previous_chapter_end
        end
      end

      # Go to next chapter
      def go_to_next_chapter
        @state.current_chapter += 1
        reset_page_position
      end

      # Go to previous chapter
      def go_to_previous_chapter
        @state.current_chapter -= 1
        reset_page_position
      end

      # Go to start of current chapter
      def go_to_start
        reset_page_position
      end

      # Go to end of current chapter
      #
      # @param content_height [Integer] Lines per page
      # @param max_page [Integer] Maximum page offset
      def go_to_end(content_height, max_page)
        if @config.view_mode == :split
          @state.right_page = max_page
          @state.left_page = [max_page - content_height, 0].max
        else
          @state.single_page = max_page
        end
      end

      # Jump to specific chapter
      #
      # @param chapter_index [Integer] Target chapter (0-based)
      def jump_to_chapter(chapter_index)
        return unless valid_chapter?(chapter_index)

        @state.current_chapter = chapter_index
        reset_page_position
      end

      # Check if can navigate to next chapter
      #
      # @return [Boolean]
      def can_go_to_next_chapter?
        @state.current_chapter < @document.chapter_count - 1
      end

      # Check if can navigate to previous chapter
      #
      # @return [Boolean]
      def can_go_to_previous_chapter?
        @state.current_chapter.positive?
      end

      private

      # Reset page position to beginning
      def reset_page_position
        @state.page_offset = 0
      end

      # Go to previous chapter and position at end
      def go_to_previous_chapter_end
        @state.current_chapter -= 1
        # Position at end will be handled by the rendering system
        # based on the chapter content
      end

      # Check if chapter index is valid
      #
      # @param index [Integer] Chapter index
      # @return [Boolean]
      def valid_chapter?(index)
        index >= 0 && index < @document.chapter_count
      end
    end
  end
end
