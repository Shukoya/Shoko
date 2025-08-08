# frozen_string_literal: true

require_relative 'terminal_output'

module EbookReader
  # TerminalBuffer manages buffered writes and differential screen updates.
  class TerminalBuffer
    attr_reader :buffer

    def initialize(output = TerminalOutput.new)
      @output = output
      @buffer = []
      @batch_mode = false
      @batch_buffer = nil
      @screen_buffer = {}
    end

    def start_frame
      @buffer = [TerminalOutput::ANSI::Control::CLEAR, TerminalOutput::ANSI::Control::HOME]
    end

    def end_frame
      @output.print(@buffer.join)
      @output.flush
    end

    def write(row, col, text)
      content = TerminalOutput::ANSI.move(row, col) + text.to_s
      if @batch_mode
        @batch_buffer << content
      else
        @buffer << content
      end
    end

    def write_differential(row, col, text)
      key = "#{row}_#{col}"
      return if @screen_buffer[key] == text

      write(row, col, text)
      @screen_buffer[key] = text
    end

    def clear_buffer_cache
      @screen_buffer.clear
    end

    def batch_write
      @batch_mode = true
      @batch_buffer = []
      yield
      @output.print(@batch_buffer.join)
      @output.flush
    ensure
      @batch_mode = false
      @batch_buffer = nil
    end
  end
end

