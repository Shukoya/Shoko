# frozen_string_literal: true

require 'io/console'
require_relative 'constants/terminal_constants'

module EbookReader
  # A utility class for terminal manipulation.
  #
  # Provides methods for clearing the screen, moving the cursor, and handling
  # raw keyboard input. It uses a double-buffering technique to minimize
  # flicker during screen updates.
  class Terminal
    # A collection of ANSI escape codes for styling and controlling the terminal.
    module ANSI
      # Text styling
      RESET = "\e[0m"
      BOLD = "\e[1m"
      DIM = "\e[2m"
      ITALIC = "\e[3m"

      # Standard colors
      BLACK = "\e[30m"
      RED = "\e[31m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      BLUE = "\e[34m"
      MAGENTA = "\e[35m"
      CYAN = "\e[36m"
      WHITE = "\e[37m"
      GRAY = "\e[90m"

      # Bright colors
      BRIGHT_RED = "\e[91m"
      BRIGHT_GREEN = "\e[92m"
      BRIGHT_YELLOW = "\e[93m"
      BRIGHT_BLUE = "\e[94m"
      BRIGHT_MAGENTA = "\e[95m"
      BRIGHT_CYAN = "\e[96m"
      BRIGHT_WHITE = "\e[97m"

      # Background colors
      BG_DARK = "\e[48;5;236m"
      BG_BRIGHT_GREEN = "\e[102m"

      # Control sequences
      module Control
        CLEAR = "\e[2J"
        HOME = "\e[H"
        HIDE_CURSOR = "\e[?25l"
        SHOW_CURSOR = "\e[?25h"
        SAVE_SCREEN = "\e[?1049h"
        RESTORE_SCREEN = "\e[?1049l"
      end

      def self.move(row, col)
        "\e[#{row};#{col}H"
      end

      def self.clear_line
        "\e[2K"
      end

      def self.clear_below
        "\e[J"
      end
    end

    @buffer = []
    @console = nil
    @size_cache = { width: nil, height: nil, checked_at: nil }
    @batch_mode = false
    @batch_buffer = nil
    @screen_buffer = {}

    class << self
      # Get current terminal dimensions.
      #
      # Falls back to default size (24x80) if terminal size cannot be determined.
      # This can happen in non-interactive environments or when IO.console is not available.
      #
      # @return [Array<Integer>] Terminal height and width as [rows, columns]
      # @example
      #   height, width = Terminal.size
      #   puts "Terminal is #{width}x#{height}"
      SIZE_CACHE_INTERVAL = 0.5

      def size
        update_size_cache if cache_expired?

        [@size_cache[:height], @size_cache[:width]]
      end

      private

      def cache_expired?
        now = Time.now
        @size_cache[:checked_at].nil? ||
          now - @size_cache[:checked_at] > SIZE_CACHE_INTERVAL
      end

      def update_size_cache
        h, w = fetch_terminal_size
        @size_cache = {
          width: w,
          height: h,
          checked_at: Time.now,
        }
      end

      def fetch_terminal_size
        IO.console.winsize
      rescue StandardError
        default_dimensions
      end

      def default_dimensions
        [Constants::TerminalConstants::DEFAULT_ROWS,
         Constants::TerminalConstants::DEFAULT_COLUMNS]
      end

      public

      def clear
        print [ANSI::Control::CLEAR, ANSI::Control::HOME].join
        $stdout.flush
      end

      def move(row, col)
        @buffer << ANSI.move(row, col)
      end

      def write(row, col, text)
        content = ANSI.move(row, col) + text.to_s
        if @batch_mode
          @batch_buffer << content
        else
          @buffer << content
        end
      end

      # Write text to the terminal only if it has changed since the last
      # write at the same position. This reduces unnecessary terminal
      # updates when content hasn't changed.
      #
      # @param row [Integer] row position
      # @param col [Integer] column position
      # @param text [String] text to write
      def write_differential(row, col, text)
        key = "#{row}_#{col}"
        return if @screen_buffer[key] == text

        write(row, col, text)
        @screen_buffer[key] = text
      end

      # Clear internal buffer tracking for differential writes
      def clear_buffer_cache
        @screen_buffer.clear
      end

      def batch_write
        @batch_mode = true
        @batch_buffer = []
        yield
        print @batch_buffer.join
        $stdout.flush
      ensure
        @batch_mode = false
        @batch_buffer = nil
      end

      def start_frame
        @buffer = [ANSI::Control::CLEAR, ANSI::Control::HOME]
      end

      def end_frame
        print @buffer.join
        $stdout.flush
      end

      def setup
        $stdout.sync = true
        @console = IO.console
        @console.raw! if @console.respond_to?(:raw!)
        print [
          ANSI::Control::SAVE_SCREEN,
          ANSI::Control::HIDE_CURSOR,
          ANSI::BG_DARK,
        ].join
        clear

        setup_signal_handlers
      end

      def cleanup
        print [
          ANSI::Control::CLEAR,
          ANSI::Control::HOME,
          ANSI::Control::SHOW_CURSOR,
          ANSI::Control::RESTORE_SCREEN,
          ANSI::RESET,
        ].join
        $stdout.flush
        @console.cooked! if @console.respond_to?(:cooked!)
        @console = nil
      end

      def read_key
        console = validate_console

        console.raw do
          read_key_with_escape_handling
        end
      rescue IO::WaitReadable
        nil
      end

      private

      def validate_console
        console = IO.console
        raise EbookReader::TerminalUnavailableError unless console

        console
      end

      def read_key_with_escape_handling
        input = $stdin.read_nonblock(1)
        return input unless input == "\e"

        read_escape_sequence(input)
      end

      def read_escape_sequence(input)
        2.times do
          input << $stdin.read_nonblock(1)
        rescue IO::WaitReadable
          break
        end

        input
      end

      public

      def read_key_blocking
        loop do
          key = read_key
          return key if key

          $stdin.wait_readable
        end
      end

      private

      def setup_signal_handlers
        %w[INT TERM].each do |signal|
          trap(signal) do
            cleanup
            exit(0)
          end
        end
      end
    end
  end
end
