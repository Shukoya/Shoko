# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # Table of Contents navigation
    class TocMode < BaseMode
      include Concerns::InputHandler

      def initialize(reader)
        super
        @selected = reader.current_chapter
      end

      ChapterItemContext = Struct.new(:chapter, :index, :row, :width, :selected)
      private_constant :ChapterItemContext

      def draw(height, width)
        draw_header(width)
        draw_chapter_list(height, width)
        draw_footer(height)
      end

      def handle_input(key)
        if exit_key?(key)
          exit_to_reading_mode
        elsif navigation_key?(key)
          handle_navigation(key)
        elsif enter_key?(key)
          select_chapter_and_exit
        end
      end

      private

      def exit_key?(key)
        escape_key?(key) || %w[t T].include?(key)
      end

      def exit_to_reading_mode
        reader.switch_mode(:read)
      end

      def handle_navigation(key)
        max_index = reader.send(:doc).chapter_count - 1
        @selected = handle_navigation_keys(key, @selected, max_index)
      end

      def select_chapter_and_exit
        reader.send(:jump_to_chapter, @selected)
        reader.switch_mode(:read)
      end

      def draw_header(width)
        terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📖 Table of Contents#{Terminal::ANSI::RESET}")
        terminal.write(1, [width - 30, 40].max,
                       "#{Terminal::ANSI::DIM}[t/ESC] Back#{Terminal::ANSI::RESET}")
      end

      def draw_chapter_list(height, width)
        list_start = 4
        list_height = height - 6
        chapters = reader.send(:doc).chapters

        visible_range = calculate_visible_range(list_height, chapters.length)

        visible_range.each_with_index do |idx, row|
          chapter = chapters[idx]
          context = ChapterItemContext.new(chapter, idx, list_start + row, width, idx == @selected)
          draw_chapter_item(context)
        end
      end

      def draw_chapter_item(context)
        title = context.chapter.title || 'Untitled'
        text = title

        if context.selected
          draw_selected_chapter_item(context, text)
        else
          draw_unselected_chapter_item(context, text)
        end
      end

      def draw_selected_chapter_item(context, text)
        terminal.write(context.row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
        terminal.write(context.row, 4,
                       "#{Terminal::ANSI::BRIGHT_WHITE}#{text[0, context.width - 6]}#{Terminal::ANSI::RESET}")
      end

      def draw_unselected_chapter_item(context, text)
        terminal.write(context.row, 4,
                       "#{Terminal::ANSI::WHITE}#{text[0, context.width - 6]}#{Terminal::ANSI::RESET}")
      end

      def draw_footer(height)
        terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Select • t/ESC Back#{Terminal::ANSI::RESET}")
      end

      def calculate_visible_range(list_height, total)
        visible_start = [@selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, total].min
        visible_start...visible_end
      end
    end
  end
end
