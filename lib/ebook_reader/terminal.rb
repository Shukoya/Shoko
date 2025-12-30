# frozen_string_literal: true

require 'io/console'
require_relative 'constants/terminal_constants'
require_relative 'terminal_output'
require_relative 'terminal_buffer'
require_relative 'terminal_input'

module EbookReader
  # Facade that preserves the historical Terminal API
  # while delegating to composable, testable components:
  # - TerminalOutput
  # - TerminalBuffer
  # - TerminalInput
  class Terminal
    # Keep ANSI nested under Terminal for compatibility
    ANSI = TerminalOutput::ANSI

    # Defines constants for special keyboard keys to abstract away different
    # terminal escape codes.
    module Keys
      UP = ["\e[A", "\eOA", 'k'].freeze
      DOWN = ["\e[B", "\eOB", 'j'].freeze
      ENTER = ["\r", "\n"].freeze
      ESCAPE = ["\e", "\x1B", 'q'].freeze
    end

    @output = TerminalOutput.new($stdout)
    @buffer_manager = TerminalBuffer.new(@output)
    @input = TerminalInput.new
    @buffer = @buffer_manager.buffer

    class << self
      # Expose a print wrapper for backward-compatible expectations in tests
      def print(str)
        @output.print(str)
      end

      def size
        @input.size
      end

      def clear
        print [ANSI::Control::CLEAR, ANSI::Control::HOME].join
        clear_buffer_cache
        $stdout.flush
      end

      def move(row, col)
        # Historically this only queued the move; keep parity
        @buffer << ANSI.move(row, col)
      end

      def write(row, col, text)
        @buffer_manager.write(row, col, text)
      end

      def write_differential(row, col, text)
        @buffer_manager.write_differential(row, col, text)
      end

      def clear_buffer_cache
        @buffer_manager.clear_buffer_cache
      end

      def batch_write(&)
        @buffer_manager.batch_write(&)
      end

      def start_frame(width: nil, height: nil)
        if width && height
          w = width.to_i
          h = height.to_i
        else
          h, w = size
        end

        @buffer_manager.start_frame(width: w, height: h)
        @buffer = @buffer_manager.buffer
      end

      def end_frame
        @buffer_manager.end_frame
      end

      # Queue raw control sequences (e.g., Kitty graphics) for the current frame.
      # These are emitted before any row diffs.
      def raw(text)
        @buffer_manager.raw(text)
      end

      def setup
        @input.setup_console
        print ANSI::Control::SAVE_SCREEN
        print ANSI::Control::HIDE_CURSOR
        print ANSI::BG_DARK
        clear
        @input.setup_signal_handlers { cleanup }
      end

      def cleanup
        print([
          ANSI::Control::CLEAR,
          ANSI::Control::HOME,
          ANSI::Control::SHOW_CURSOR,
          ANSI::Control::RESTORE_SCREEN,
          ANSI::RESET,
        ].join)
        @output.flush
        @input.cleanup_console
      end

      def read_key
        @input.read_key
      end

      def read_key_blocking(timeout: nil)
        @input.read_key_blocking(timeout: timeout)
      end

      # Mouse helpers
      def enable_mouse
        @input.enable_mouse
      end

      def disable_mouse
        @input.disable_mouse
      end

      def read_input_with_mouse(timeout: nil)
        @input.read_input_with_mouse(timeout: timeout)
      end
    end
  end
end
