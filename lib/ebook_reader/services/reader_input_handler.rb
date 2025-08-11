# frozen_string_literal: true

require_relative 'reader_input_handler/navigation_handlers'
require_relative 'layout_service'

module EbookReader
  module Services
    # Handles user input for the Reader class so the reader itself
    # can focus on state management and rendering.
    class ReaderInputHandler
      include Concerns::InputHandler
      include NavigationHandlers

      def initialize(reader)
        @reader = reader
      end

      def process_input(key)
        return unless key

        Thread.current[:ebook_reader_last_key] = key
        handlers = handlers_for_mode(current_mode)
        (handlers[key] || handlers[:__default__])&.call(key)
      ensure
        Thread.current[:ebook_reader_last_key] = nil
      end

      private

      def current_mode
        state = @reader.instance_variable_get(:@state)
        state ? state.mode : :read
      end

      def handlers_for_mode(mode)
        case mode
        when :help then help_mode_handlers
        when :toc then toc_mode_handlers
        when :bookmarks then bookmarks_mode_handlers
        else read_mode_handlers
        end
      end

      def help_mode_handlers
        # Any key returns to read mode
        { __default__: ->(_) { @reader.switch_mode(:read) } }
      end

      def read_mode_handlers
        # Build fresh each time to reflect dynamic/absolute navigation
        nav = navigation_handlers_for_current_mode || {}
        basic_reading_handlers.merge(toggle_handlers).merge(nav)
      end

      def basic_reading_handlers
        {
          'q' => ->(_) { @reader.quit_to_menu },
          'Q' => ->(_) { @reader.quit_application },
          '?' => ->(_) { @reader.switch_mode(:help) },
          't' => ->(_) { @reader.send(:open_toc) },
          'T' => ->(_) { @reader.send(:open_toc) },
          'b' => ->(_) { @reader.add_bookmark },
          'B' => ->(_) { @reader.send(:open_bookmarks) },
          "\u0001" => ->(_) { @reader.send(:open_annotations) },
        }
      end

      def toggle_handlers
        {
          'v' => ->(_) { @reader.toggle_view_mode },
          'V' => ->(_) { @reader.toggle_view_mode },
          'P' => ->(_) { @reader.toggle_page_numbering_mode },
          '+' => ->(_) { @reader.increase_line_spacing },
          '-' => ->(_) { @reader.decrease_line_spacing },
        }
      end

      def navigation_handlers_for_current_mode
        height, width = Terminal.size
        col_width, content_height = Services::LayoutService.calculate_metrics(width, height, @reader.config.view_mode)
        content_height = Services::LayoutService.adjust_for_line_spacing(content_height, @reader.config.line_spacing)

        chapter = @reader.doc.get_chapter(@reader.current_chapter)
        return unless chapter

        wrapped = @reader.send(:wrap_lines, chapter.lines || [], col_width)
        max_page = [wrapped.size - content_height, 0].max

        if @reader.config.page_numbering_mode == :dynamic
          dynamic_navigation_handlers
        else
          absolute_navigation_handlers(content_height, max_page)
        end
      end

      def absolute_navigation_handlers(content_height, max_page)
        {
          'j' => ->(_) { scroll_down_with_max(max_page) },
          "\e[B" => ->(_) { scroll_down_with_max(max_page) },
          "\eOB" => ->(_) { scroll_down_with_max(max_page) },
          'k' => ->(_) { @reader.scroll_up },
          "\e[A" => ->(_) { @reader.scroll_up },
          "\eOA" => ->(_) { @reader.scroll_up },
          'l' => ->(_) { next_page_with_params(content_height, max_page) },
          ' ' => ->(_) { next_page_with_params(content_height, max_page) },
          "\e[C" => ->(_) { next_page_with_params(content_height, max_page) },
          "\eOC" => ->(_) { next_page_with_params(content_height, max_page) },
          'h' => ->(_) { prev_page_with_params(content_height) },
          "\e[D" => ->(_) { prev_page_with_params(content_height) },
          "\eOD" => ->(_) { prev_page_with_params(content_height) },
          'n' => ->(_) { handle_next_chapter },
          'N' => ->(_) { handle_next_chapter },
          'p' => ->(_) { handle_prev_chapter },
          'P' => ->(_) { handle_prev_chapter },
          'g' => ->(_) { @reader.send(:reset_pages) },
          'G' => ->(_) { go_to_end_with_params(content_height, max_page) },
        }
      end

      def dynamic_navigation_handlers
        {
          'j' => ->(_) { @reader.next_page },
          "\e[B" => ->(_) { @reader.next_page },
          "\eOB" => ->(_) { @reader.next_page },
          'l' => ->(_) { @reader.next_page },
          ' ' => ->(_) { @reader.next_page },
          "\e[C" => ->(_) { @reader.next_page },
          "\eOC" => ->(_) { @reader.next_page },
          'k' => ->(_) { @reader.prev_page },
          "\e[A" => ->(_) { @reader.prev_page },
          "\eOA" => ->(_) { @reader.prev_page },
          'h' => ->(_) { @reader.prev_page },
          "\e[D" => ->(_) { @reader.prev_page },
          "\eOD" => ->(_) { @reader.prev_page },
          'n' => ->(_) { handle_next_chapter },
          'N' => ->(_) { handle_next_chapter },
          'p' => ->(_) { handle_prev_chapter },
          'P' => ->(_) { handle_prev_chapter },
          'g' => ->(_) { @reader.go_to_start },
          'G' => ->(_) { @reader.go_to_end },
        }
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

      def toc_mode_handlers
        nav_keys = {
          'j' => true, "\e[B" => true, "\eOB" => true,
          'k' => true, "\e[A" => true, "\eOA" => true
        }
        handlers = {
          't' => ->(_) { @reader.switch_mode(:read) },
          'T' => ->(_) { @reader.switch_mode(:read) },
          "\r" => ->(_) { handle_toc_selection },
          "\n" => ->(_) { handle_toc_selection },
        }
        nav_keys.each_key do |k|
          handlers[k] = ->(key) { handle_toc_navigation(key) }
        end
        # ESC as default exit
        handlers[:__default__] = ->(k) { @reader.switch_mode(:read) if escape_key?(k) }
        handlers
      end

      def toc_exit_key?(key)
        %w[t T].include?(key) || escape_key?(key)
      end

      def handle_toc_navigation(key)
        state = @reader.instance_variable_get(:@state)
        selected = handle_navigation_keys(
          key,
          state.toc_selected,
          @reader.doc.chapter_count - 1
        )
        state.toc_selected = selected
      end

      def handle_toc_selection
        chapter_index = @reader.instance_variable_get(:@state).toc_selected
        @reader.send(:jump_to_chapter, chapter_index)
      end

      def bookmarks_mode_handlers
        bookmarks = @reader.instance_variable_get(:@bookmarks)
        if bookmarks.empty?
          { __default__: lambda { |k|
            @reader.switch_mode(:read) if ['B'].include?(k) || escape_key?(k)
          } }
        else
          handlers = {}
          nav_keys = {
            'j' => true, "\e[B" => true, "\eOB" => true,
            'k' => true, "\e[A" => true, "\eOA" => true
          }
          nav_keys.each_key do |k|
            handlers[k] = ->(key) { handle_bookmark_navigation_key(bookmarks, key) }
          end
          handlers['B'] = ->(_) { @reader.switch_mode(:read) }
          handlers["\r"] = ->(_) { @reader.send(:jump_to_bookmark) }
          handlers['d'] = ->(_) { @reader.send(:delete_selected_bookmark) }
          handlers[:__default__] = ->(k) { @reader.switch_mode(:read) if escape_key?(k) }
          handlers
        end
      end

      def handle_bookmark_navigation_key(bookmarks, key)
        state = @reader.instance_variable_get(:@state)
        selected = handle_navigation_keys(
          key,
          state.bookmark_selected,
          bookmarks.length - 1
        )
        state.bookmark_selected = selected
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
          bookmarks.length - 1
        )
        @reader.instance_variable_set(:@bookmark_selected, selected)
      end

      def handle_empty_bookmarks_input(key)
        @reader.switch_mode(:read) if ['B'].include?(key) || escape_key?(key)
      end

      # All interaction is driven via #process_input; helper methods remain private.
    end
  end
end
