# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # DEPRECATED: Legacy navigation command class
    # This class is being phased out in favor of the unified Input system
    # with Domain commands. Navigation now flows through:
    # Input::Commands -> Domain::Commands -> Services
    class NavigationCommand
      COMMANDS = {
        'j' => :scroll_down,
        "\e[B" => :scroll_down,
        "\eOB" => :scroll_down,
        'k' => :scroll_up,
        "\e[A" => :scroll_up,
        "\eOA" => :scroll_up,
        'l' => :next_page,
        ' ' => :next_page,
        "\e[C" => :next_page,
        "\eOC" => :next_page,
        'h' => :prev_page,
        "\e[D" => :prev_page,
        "\eOD" => :prev_page,
        'n' => :next_chapter,
        'N' => :next_chapter,
        'p' => :prev_chapter,
        'P' => :prev_chapter,
        'g' => :go_to_start,
        'G' => :go_to_end,
      }.freeze

      def self.execute(key, reader)
        # Use the unified Input system instead of direct method calls
        command = COMMANDS[key]
        return unless command

        # Route through the Input system for proper command handling
        Input::Commands.execute(command, reader, key)
      end
    end

    # Handles the main reading view and navigation for the EPUB reader.
    # This mode is responsible for rendering the book content and processing
    # reading-related keyboard shortcuts.
    class ReadingMode < BaseMode
      def draw(height, width)
        if config.view_mode == :split
          draw_split_view(height, width)
        else
          draw_single_view(height, width)
        end
      end

      def handle_input(key)
        if navigation_key?(key)
          handle_navigation(key)
        elsif mode_switch_key?(key)
          handle_mode_switch(key)
        elsif view_adjustment_key?(key)
          handle_view_adjustment(key)
        elsif action_key?(key)
          handle_action(key)
        end
      end

      private

      def navigation_key?(key)
        %w[j k l h n p g G].include?(key) ||
          ["\e[A", "\e[B", "\e[C", "\e[D", "\eOA", "\eOB", "\eOC", "\eOD", ' '].include?(key)
      end

      def mode_switch_key?(key)
        %w[t T b B ?].include?(key)
      end

      def view_adjustment_key?(key)
        %w[v V + -].include?(key)
      end

      def action_key?(key)
        %w[q Q].include?(key)
      end

      def handle_navigation(key)
        NavigationCommand.execute(key, reader)
      end

      def handle_mode_switch(key)
        case key
        when 't', 'T'
          # Use domain command for mode switching
          Input::Commands.execute(:open_toc, reader, key)
        when 'b'
          # Bookmark operations remain direct for now (complex context needed)
          reader.add_bookmark
        when 'B'
          # Use domain command for mode switching
          Input::Commands.execute(:open_bookmarks, reader, key)
        when '?'
          # Use domain command for mode switching
          Input::Commands.execute(:show_help, reader, key)
        end
      end

      def handle_view_adjustment(key)
        case key
        when 'v', 'V' then reader.toggle_view_mode
        when '+' then reader.increase_line_spacing
        when '-' then reader.decrease_line_spacing
        end
      end

      def handle_action(key)
        case key
        when 'q'
          # Use domain command for application lifecycle
          Input::Commands.execute(:quit_to_menu, reader, key)
        when 'Q'
          # Use domain command for application lifecycle
          Input::Commands.execute(:quit, reader, key)
        end
      end

      def draw_split_view(height, width)
        reader.send(:draw_split_screen, height, width)
      end

      def draw_single_view(height, width)
        reader.send(:draw_single_screen, height, width)
      end
    end
  end
end
