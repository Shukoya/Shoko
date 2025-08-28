# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      # Clean service for page calculations without UI dependencies.
      # Replaces the mixed concerns in the original PageManager.
      class PageCalculatorService
        def initialize(state_store, text_wrapper = nil)
          @state_store = state_store
          @text_wrapper = text_wrapper || DefaultTextWrapper.new
          @cache = {}
        end

        # Calculate total pages for a chapter
        #
        # @param chapter_index [Integer] Chapter index
        # @return [Integer] Number of pages in chapter
        def calculate_pages_for_chapter(chapter_index)
          current_state = @state_store.current_state
          cache_key = build_cache_key(chapter_index, current_state)

          @cache[cache_key] ||= perform_page_calculation(chapter_index, current_state)
        end

        # Calculate page position within chapter
        #
        # @param chapter_index [Integer] Chapter index
        # @param line_offset [Integer] Line offset within chapter
        # @return [Integer] Page number within chapter
        def calculate_page_from_line(_chapter_index, line_offset)
          lines_per_page = calculate_lines_per_page
          return 0 if lines_per_page <= 0

          (line_offset.to_f / lines_per_page).floor
        end

        # Calculate line offset from page number
        #
        # @param chapter_index [Integer] Chapter index
        # @param page_number [Integer] Page number within chapter
        # @return [Integer] Line offset
        def calculate_line_from_page(_chapter_index, page_number)
          lines_per_page = calculate_lines_per_page
          page_number * lines_per_page
        end

        # Calculate total pages across all chapters
        #
        # @param chapter_count [Integer] Total number of chapters
        # @return [Integer] Total pages
        def calculate_total_pages(chapter_count)
          (0...chapter_count).sum { |i| calculate_pages_for_chapter(i) }
        end

        # Calculate global page number
        #
        # @param chapter_index [Integer] Current chapter
        # @param page_within_chapter [Integer] Page within current chapter
        # @param total_chapters [Integer] Total chapters
        # @return [Integer] Global page number
        def calculate_global_page_number(chapter_index, page_within_chapter, _total_chapters)
          pages_before = (0...chapter_index).sum { |i| calculate_pages_for_chapter(i) }
          pages_before + page_within_chapter + 1
        end

        # Clear calculation cache
        def clear_cache
          @cache.clear
        end

        # Clear cache for specific dimensions
        #
        # @param width [Integer] Terminal width
        # @param height [Integer] Terminal height
        def clear_cache_for_dimensions(width, height)
          @cache.delete_if { |key, _| key.include?("#{width}x#{height}") }
        end

        private

        def perform_page_calculation(chapter_index, state)
          lines_per_page = calculate_lines_per_page
          return 0 if lines_per_page <= 0

          chapter_lines = get_chapter_lines(chapter_index, state)
          wrapped_lines = @text_wrapper.wrap_chapter_lines(chapter_lines, calculate_column_width)

          (wrapped_lines.size.to_f / lines_per_page).ceil
        end

        def calculate_lines_per_page
          state = @state_store.current_state
          terminal_height = state.dig(:ui, :terminal_height) || 24

          # Account for header and footer
          content_height = terminal_height - 3 # header(1) + footer(1) + padding(1)

          # Adjust for line spacing
          line_spacing = state.dig(:config, :line_spacing) || :normal
          case line_spacing
          when :relaxed
            [content_height / 2, 1].max
          else
            content_height
          end
        end

        def calculate_column_width
          state = @state_store.current_state
          terminal_width = state.dig(:ui, :terminal_width) || 80
          view_mode = state.dig(:reader, :view_mode) || :split

          case view_mode
          when :single
            terminal_width - 4 # Account for padding
          when :split
            (terminal_width / 2) - 4 # Two columns with padding
          else
            terminal_width - 4
          end
        end

        def get_chapter_lines(_chapter_index, _state)
          # This would interface with the document/EPUB system
          # For now, return empty array as placeholder
          []
        end

        def build_cache_key(chapter_index, state)
          width = state.dig(:ui, :terminal_width) || 80
          height = state.dig(:ui, :terminal_height) || 24
          view_mode = state.dig(:reader, :view_mode) || :split
          line_spacing = state.dig(:config, :line_spacing) || :normal

          "#{chapter_index}_#{width}x#{height}_#{view_mode}_#{line_spacing}"
        end
      end

      # Default text wrapping implementation
      class DefaultTextWrapper
        def wrap_chapter_lines(lines, column_width)
          return [] if lines.empty? || column_width <= 0

          wrapped = []
          lines.each do |line|
            if line.length <= column_width
              wrapped << line
            else
              wrapped.concat(wrap_long_line(line, column_width))
            end
          end
          wrapped
        end

        private

        def wrap_long_line(line, width)
          words = line.split(/\s+/)
          wrapped_lines = []
          current_line = ''

          words.each do |word|
            if current_line.empty?
              current_line = word
            elsif "#{current_line} #{word}".length <= width
              current_line += " #{word}"
            else
              wrapped_lines << current_line
              current_line = word
            end
          end

          wrapped_lines << current_line unless current_line.empty?
          wrapped_lines
        end
      end
    end
  end
end
