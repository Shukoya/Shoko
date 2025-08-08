# frozen_string_literal: true

require 'io/console'
require_relative 'constants/terminal_constants'

module EbookReader
  # TerminalInput encapsulates input reading, console modes, and size queries.
  class TerminalInput
    SIZE_CACHE_INTERVAL = 0.5

    def initialize
      @console = nil
      @size_cache = { width: nil, height: nil, checked_at: nil }
    end

    def size
      update_size_cache if cache_expired?
      [@size_cache[:height], @size_cache[:width]]
    end

    def setup_console
      $stdout.sync = true
      @console = IO.console
      @console.raw! if @console&.respond_to?(:raw!)
    end

    def cleanup_console
      @console.cooked! if @console&.respond_to?(:cooked!)
      @console = nil
    end

    def with_raw_console
      console = validate_console
      console.raw do
        yield
      end
    end

    def read_key
      with_raw_console do
        read_key_with_escape_handling
      end
    rescue IO::WaitReadable, IO::EAGAINWaitReadable
      nil
    end

    def read_key_blocking
      loop do
        key = read_key
        return key if key
        $stdin.wait_readable
      end
    end

    # Mouse support
    def enable_mouse
      $stdout.print "\e[?1003h\e[?1006h"
      $stdout.flush
    end

    def disable_mouse
      $stdout.print "\e[?1003l\e[?1006l"
      $stdout.flush
    end

    def read_input_with_mouse
      input = read_key_blocking
      return nil unless input

      if input.start_with?("\e[<")
        while input[-1] != 'm' && input[-1] != 'M'
          extra = read_key
          break unless extra
          input += extra
        end
      end

      input
    end

    def setup_signal_handlers(&cleanup_callback)
      %w[INT TERM].each do |signal|
        trap(signal) do
          cleanup_callback.call if cleanup_callback
          exit(0)
        end
      end
    end

    private

    def cache_expired?
      now = Time.now
      @size_cache[:checked_at].nil? || now - @size_cache[:checked_at] > SIZE_CACHE_INTERVAL
    end

    def update_size_cache
      h, w = fetch_terminal_size
      @size_cache = { width: w, height: h, checked_at: Time.now }
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
  end
end

