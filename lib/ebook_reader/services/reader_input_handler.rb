# frozen_string_literal: true

module EbookReader
  module Services
    # Handles user input for the Reader class so the reader itself
    # can focus on state management and rendering.
    class ReaderInputHandler
      include Concerns::InputHandler

      def initialize(reader)
        @reader = reader
      end

      def process_input(key)
        return unless key

        case @reader.instance_variable_get(:@mode)
        when :help
          @reader.switch_mode(:read)
        when :toc
          handle_toc_input(key)
        when :bookmarks
          handle_bookmarks_input(key)
        else
          handle_reading_input(key)
        end
      end

      def handle_reading_input(key)
        case key
        when 'q' then @reader.quit_to_menu
        when 'Q' then @reader.quit_application
        when '?' then @reader.switch_mode(:help)
        when 't', 'T' then @reader.send(:open_toc)
        when 'b' then @reader.add_bookmark
        when 'B' then @reader.send(:open_bookmarks)
        when 'v', 'V' then @reader.toggle_view_mode
        when 'P' then @reader.toggle_page_numbering_mode
        when '+' then @reader.increase_line_spacing
        when '-' then @reader.decrease_line_spacing
        else handle_navigation_input(key)
        end
      end

      def handle_navigation_input(key)
        if @reader.config.page_numbering_mode == :dynamic
          handle_navigation_input_dynamic(key)
        else
          handle_navigation_input_absolute(key)
        end
      end

      def handle_navigation_input_dynamic(key)
        case key
        when 'j', 'k', "\e[B", "\eOB", "\e[A", "\eOA"
          if ['j', "\e[B", "\eOB"].include?(key)
            @reader.next_page
          else
            @reader.prev_page
          end
        when 'l', ' ', "\e[C", "\eOC"
          @reader.next_page
        when 'h', "\e[D", "\eOD"
          @reader.prev_page
        when 'n', 'N'
          @reader.next_chapter
        when 'p', 'P'
          @reader.prev_chapter
        when 'g'
          @reader.instance_variable_set(:@current_page_index, 0)
          @reader.send(:update_chapter_from_page_index)
        when 'G'
          pm = @reader.instance_variable_get(:@page_manager)
          if pm
            @reader.instance_variable_set(:@current_page_index, pm.total_pages - 1)
            @reader.send(:update_chapter_from_page_index)
          end
        end
      end

      def handle_navigation_input_absolute(key)
        height, width = Terminal.size
        col_width, content_height = @reader.send(:get_layout_metrics, width, height)
        content_height = @reader.send(:adjust_for_line_spacing, content_height)

        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        wrapped = @reader.send(:wrap_lines, chapter.lines || [], col_width)
        max_page = [wrapped.size - content_height, 0].max

        navigate_by_key(key, content_height, max_page)
      end

      def navigate_by_key(key, content_height, max_page)
        case key
        when 'j', "\e[B", "\eOB" then scroll_down_with_max(max_page)
        when 'k', "\e[A", "\eOA" then @reader.scroll_up
        when 'l', ' ', "\e[C", "\eOC" then next_page_with_params(content_height, max_page)
        when 'h', "\e[D", "\eOD" then prev_page_with_params(content_height)
        when 'n', 'N' then handle_next_chapter
        when 'p', 'P' then handle_prev_chapter
        when 'g' then @reader.send(:reset_pages)
        when 'G' then go_to_end_with_params(content_height, max_page)
        end
      end

      def scroll_down_with_max(max_page)
        @reader.instance_variable_set(:@max_page, max_page)
        @reader.scroll_down
      end

      def next_page_with_params(_content_height, _max_page)
        @reader.next_page
      end

      def prev_page_with_params(_content_height)
        @reader.prev_page
      end

      def go_to_end_with_params(_content_height, _max_page)
        @reader.go_to_end
      end

      def handle_next_chapter
        return unless @reader.current_chapter < @reader.doc.chapter_count - 1

        @reader.next_chapter
      end

      def handle_prev_chapter
        @reader.prev_chapter if @reader.current_chapter.positive?
      end

      def handle_toc_input(key)
        if %w[t T].include?(key) || escape_key?(key)
          @reader.switch_mode(:read)
        elsif navigation_key?(key)
          selected = handle_navigation_keys(
            key,
            @reader.instance_variable_get(:@toc_selected),
            @reader.doc.chapter_count - 1
          )
          @reader.instance_variable_set(:@toc_selected, selected)
        elsif enter_key?(key)
          chapter_index = @reader.instance_variable_get(:@toc_selected)
          @reader.send(:jump_to_chapter, chapter_index)
        end
      end

      def handle_bookmarks_input(key)
        bookmarks = @reader.instance_variable_get(:@bookmarks)
        return handle_empty_bookmarks_input(key) if bookmarks.empty?

        if ['B'].include?(key) || escape_key?(key)
          @reader.switch_mode(:read)
        elsif navigation_key?(key)
          selected = handle_navigation_keys(
            key,
            @reader.instance_variable_get(:@bookmark_selected),
            bookmarks.length - 1
          )
          @reader.instance_variable_set(:@bookmark_selected, selected)
        elsif enter_key?(key)
          @reader.send(:jump_to_bookmark)
        elsif %w[d D].include?(key)
          @reader.send(:delete_selected_bookmark)
        end
      end

      def handle_empty_bookmarks_input(key)
        @reader.switch_mode(:read) if ['B'].include?(key) || escape_key?(key)
      end
    end
  end
end
