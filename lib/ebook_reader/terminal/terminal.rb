# frozen_string_literal: true

require_relative '../terminal_output'
require 'io/console'
require_relative '../constants'

module EbookReader
  module TerminalAbstraction
    class Interface
      def self.instance
        @instance ||= new
      end

      def initialize
        @output = TerminalOutput.new
      end

      # === Core Terminal Operations ===

      def clear
        print [ANSI::Control::CLEAR, ANSI::Control::HOME].join
        flush
      end

      def move(row, col)
        print ANSI.move(row, col)
      end

      def write(row, col, text)
        move(row, col)
        print text
      end

      def flush
        @output.flush
      end

      def print(str)
        @output.print(str)
      end

      def size
        if IO.respond_to?(:console) && IO.console
          h, w = IO.console.winsize
          [h, w]
        else
          [Constants::DEFAULT_HEIGHT, Constants::DEFAULT_WIDTH]
        end
      rescue StandardError
        [Constants::DEFAULT_HEIGHT, Constants::DEFAULT_WIDTH]
      end

      # === Setup/Cleanup ===

      def setup
        print ANSI::Control::SAVE_SCREEN
        print ANSI::Control::HIDE_CURSOR
        print ANSI::BG_DARK
        clear
      end

      def cleanup
        print [
          ANSI::Control::CLEAR,
          ANSI::Control::HOME,
          ANSI::Control::SHOW_CURSOR,
          ANSI::Control::RESTORE_SCREEN,
          ANSI::RESET,
        ].join
        flush
      end

      # === Semantic Color Methods ===

      def primary_text(text)
        "#{ANSI::WHITE}#{text}#{ANSI::RESET}"
      end

      def secondary_text(text)
        "#{ANSI::GRAY}#{text}#{ANSI::RESET}"
      end

      def accent_text(text)
        "#{ANSI::BLUE}#{text}#{ANSI::RESET}"
      end

      def success_text(text)
        "#{ANSI::GREEN}#{text}#{ANSI::RESET}"
      end

      def warning_text(text)
        "#{ANSI::YELLOW}#{text}#{ANSI::RESET}"
      end

      def error_text(text)
        "#{ANSI::RED}#{text}#{ANSI::RESET}"
      end

      def highlight_text(text)
        "#{ANSI::CYAN}#{text}#{ANSI::RESET}"
      end

      def selected_text(text)
        "\e[7m -> #{text}\e[0m"
      end

      def dimmed_text(text)
        "#{ANSI::GRAY}#{text}#{ANSI::RESET}"
      end

      def chapter_info(text)
        "#{ANSI::BLUE}#{text}#{ANSI::RESET}"
      end

      def progress_info(text)
        "#{ANSI::BLUE}#{text}#{ANSI::RESET}"
      end

      def mode_indicator(text)
        "#{ANSI::YELLOW}#{text}#{ANSI::RESET}"
      end

      def status_message(text)
        "#{ANSI::BG_BLUE}#{ANSI::BRIGHT_YELLOW}#{text}#{ANSI::RESET}"
      end

      def divider
        "#{ANSI::GRAY}│#{ANSI::RESET}"
      end

      def navigation_hint(text)
        "#{ANSI::GRAY}#{text}#{ANSI::RESET}"
      end

      def content_text(text)
        "#{ANSI::WHITE}#{text}#{ANSI::RESET}"
      end

      def selected_item(text)
        "#{ANSI::GREEN}▸ #{ANSI::RESET}#{ANSI::BRIGHT_WHITE}#{text}#{ANSI::RESET}"
      end

      def unselected_item(text)
        "#{ANSI::WHITE}#{text}#{ANSI::RESET}"
      end

      def cursor_indicator
        "#{ANSI::GRAY}^#{ANSI::RESET}"
      end

      def page_indicator(text)
        "#{ANSI::GRAY}#{text}#{ANSI::RESET}"
      end

      # Direct access to ANSI constants when needed
      ANSI = TerminalOutput::ANSI
    end
  end
end
