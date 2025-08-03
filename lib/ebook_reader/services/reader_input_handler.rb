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

        send(mode_handler_method, key)
      end

      private

      def mode_handler_method
        "handle_#{@reader.instance_variable_get(:@mode)}_mode"
      end

      def handle_help_mode(_key)
        @reader.switch_mode(:read)
      end

      def handle_toc_mode(key)
        handle_toc_input(key)
      end

      def handle_bookmarks_mode(key)
        handle_bookmarks_input(key)
      end

      def handle_read_mode(key)
        handle_reading_input(key)
      end

      def handle_reading_input(key)
        handler = reading_input_handlers[key]

        if handler
          handler.call
        else
          handle_navigation_input(key)
        end
      end

      def reading_input_handlers
        @reading_handlers ||= basic_reading_handlers.merge(toggle_handlers)
      end

      def basic_reading_handlers
        {
          'q' => -> { @reader.quit_to_menu },
          'Q' => -> { @reader.quit_application },
          '?' => -> { @reader.switch_mode(:help) },
          't' => -> { @reader.send(:open_toc) },
          'T' => -> { @reader.send(:open_toc) },
          'b' => -> { @reader.add_bookmark },
          'B' => -> { @reader.send(:open_bookmarks) },
        }
      end

      def toggle_handlers
        {
          'v' => -> { @reader.toggle_view_mode },
          'V' => -> { @reader.toggle_view_mode },
          'P' => -> { @reader.toggle_page_numbering_mode },
          '+' => -> { @reader.increase_line_spacing },
          '-' => -> { @reader.decrease_line_spacing },
        }
      end

      def handle_navigation_input(key)
        if @reader.config.page_numbering_mode == :dynamic
          handle_navigation_input_dynamic(key)
        else
          handle_navigation_input_absolute(key)
        end
      end

      def handle_navigation_input_dynamic(key)
        handler = dynamic_navigation_handlers[key]
        handler&.call
      end

      def dynamic_navigation_handlers
        @dynamic_handlers ||= basic_nav_handlers
                               .merge(chapter_nav_handlers)
                               .merge(go_handlers)
      end

      def basic_nav_handlers
        next_keys.merge(prev_keys)
      end

      def next_keys
        {
          'j' => -> { @reader.next_page },
          "\e[B" => -> { @reader.next_page },
          "\eOB" => -> { @reader.next_page },
          'l' => -> { @reader.next_page },
          ' ' => -> { @reader.next_page },
          "\e[C" => -> { @reader.next_page },
          "\eOC" => -> { @reader.next_page },
        }
      end

      def prev_keys
        {
          'k' => -> { @reader.prev_page },
          "\e[A" => -> { @reader.prev_page },
          "\eOA" => -> { @reader.prev_page },
          'h' => -> { @reader.prev_page },
          "\e[D" => -> { @reader.prev_page },
          "\eOD" => -> { @reader.prev_page },
        }
      end

      def chapter_nav_handlers
        {
          'n' => -> { @reader.next_chapter },
          'N' => -> { @reader.next_chapter },
          'p' => -> { @reader.prev_chapter },
          'P' => -> { @reader.prev_chapter },
        }
      end

      def go_handlers
        {
          'g' => -> { go_to_start_dynamic },
          'G' => -> { go_to_end_dynamic },
        }
      end

      def go_to_start_dynamic
        @reader.instance_variable_set(:@current_page_index, 0)
        @reader.send(:update_chapter_from_page_index)
      end

      def go_to_end_dynamic
        pm = @reader.instance_variable_get(:@page_manager)
        return unless pm

        @reader.instance_variable_set(:@current_page_index, pm.total_pages - 1)
        @reader.send(:update_chapter_from_page_index)
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
        if toc_exit_key?(key)
          @reader.switch_mode(:read)
        elsif navigation_key?(key)
          handle_toc_navigation(key)
        elsif enter_key?(key)
          handle_toc_selection
        end
      end

      def toc_exit_key?(key)
        %w[t T].include?(key) || escape_key?(key)
      end

      def handle_toc_navigation(key)
        selected = handle_navigation_keys(
          key,
          @reader.instance_variable_get(:@toc_selected),
          @reader.doc.chapter_count - 1,
        )
        @reader.instance_variable_set(:@toc_selected, selected)
      end

      def handle_toc_selection
        chapter_index = @reader.instance_variable_get(:@toc_selected)
        @reader.send(:jump_to_chapter, chapter_index)
      end

      def handle_bookmarks_input(key)
        bookmarks = @reader.instance_variable_get(:@bookmarks)

        if bookmarks.empty?
          handle_empty_bookmarks_input(key)
        else
          handle_populated_bookmarks_input(key, bookmarks)
        end
      end

      def handle_populated_bookmarks_input(key, bookmarks)
        if bookmark_exit_key?(key)
          @reader.switch_mode(:read)
        elsif navigation_key?(key)
          handle_bookmark_navigation(key, bookmarks)
        elsif enter_key?(key)
          @reader.send(:jump_to_bookmark)
        elsif delete_key?(key)
          @reader.send(:delete_selected_bookmark)
        end
      end

      def bookmark_exit_key?(key)
        ['B'].include?(key) || escape_key?(key)
      end

      def delete_key?(key)
        %w[d D].include?(key)
      end

      def handle_bookmark_navigation(key, bookmarks)
        selected = handle_navigation_keys(
          key,
          @reader.instance_variable_get(:@bookmark_selected),
          bookmarks.length - 1,
        )
        @reader.instance_variable_set(:@bookmark_selected, selected)
      end

      def handle_empty_bookmarks_input(key)
        @reader.switch_mode(:read) if ['B'].include?(key) || escape_key?(key)
      end
    end
  end
end
