# frozen_string_literal: true

require_relative 'terminal_output'
require_relative 'helpers/text_metrics'

module EbookReader
  # TerminalBuffer manages buffered writes and differential screen updates.
  class TerminalBuffer
    class Frame
      CONTINUATION = :_wide_continuation

      def initialize(width, height)
        @width = width.to_i
        @height = height.to_i
        @chars = Array.new(@height) { Array.new(@width, ' ') }
        @styles = Array.new(@height) { Array.new(@width, nil) }
      end

      def write(row, col, text)
        return if @width <= 0 || @height <= 0

        row_i = row.to_i - 1
        col_i = col.to_i - 1
        return if row_i.negative? || row_i >= @height
        return if col_i.negative?
        return if col_i >= @width

        current_style = ''
        col_pos = col_i

        String(text).scan(EbookReader::Helpers::TextMetrics::TOKEN_REGEX).each do |token|
          if token.start_with?("\e[")
            if token.end_with?('m')
              current_style = '' if token == TerminalOutput::ANSI::RESET
              current_style = current_style + token unless token == TerminalOutput::ANSI::RESET
            end
            next
          end

          break if col_pos >= @width

          if token == "\t"
            tab_size = EbookReader::Helpers::TextMetrics::TAB_SIZE
            spaces = tab_size - (col_pos % tab_size)
            spaces.times do
              break if col_pos >= @width

              clear_wide_overlap(row_i, col_pos)
              @chars[row_i][col_pos] = ' '
              @styles[row_i][col_pos] = current_style.empty? ? nil : current_style
              col_pos += 1
            end
            next
          end

          next if token == "\e"

          cluster = token == "\n" || token == "\r" ? ' ' : token
          width = EbookReader::Helpers::TextMetrics.display_width_for(cluster)
          next if width <= 0

          remaining = @width - col_pos
          break if width > remaining

          clear_wide_overlap(row_i, col_pos)

          @chars[row_i][col_pos] = cluster
          @styles[row_i][col_pos] = current_style.empty? ? nil : current_style

          if width > 1
            (1...width).each do |delta|
              break if col_pos + delta >= @width

              clear_wide_overlap(row_i, col_pos + delta)
              @chars[row_i][col_pos + delta] = CONTINUATION
              @styles[row_i][col_pos + delta] = nil
            end
          end

          col_pos += width
        end
      rescue StandardError
        nil
      end

      def rendered_rows
        (0...@height).map { |row_i| render_row(row_i) }
      end

      private

      def clear_wide_overlap(row_i, col_i)
        cell = @chars[row_i][col_i]
        if cell == CONTINUATION && col_i.positive?
          @chars[row_i][col_i - 1] = ' '
          @styles[row_i][col_i - 1] = nil
        elsif col_i + 1 < @width && @chars[row_i][col_i + 1] == CONTINUATION
          @chars[row_i][col_i + 1] = ' '
          @styles[row_i][col_i + 1] = nil
        end
        @chars[row_i][col_i] = ' '
        @styles[row_i][col_i] = nil
      end

      def render_row(row_i)
        chars = @chars[row_i]
        styles = @styles[row_i]
        last_col = last_non_blank_col(chars, styles)
        return '' if last_col < 0

        out = +''
        active_style = nil
        run = +''

        col = 0
        while col <= last_col
          ch = chars[col]
          if ch == CONTINUATION
            col += 1
            next
          end

          style = styles[col]
          style = nil if style.nil? || style.empty?

          if style != active_style
            flush_run(out, run, active_style)
            run = +''
            active_style = style
          end

          run << (ch || ' ')
          col += 1
        end

        flush_run(out, run, active_style)
        out
      end

      def last_non_blank_col(chars, styles)
        idx = chars.length - 1
        while idx >= 0
          ch = chars[idx]
          style = styles[idx]
          return idx if ch == CONTINUATION
          return idx if style && !style.empty?
          return idx if ch && ch != ' '

          idx -= 1
        end
        -1
      end

      def flush_run(out, run, style)
        return if run.empty?

        if style
          out << style << run << TerminalOutput::ANSI::RESET
        else
          out << run
        end
      end
    end

    attr_reader :buffer

    def initialize(output = TerminalOutput.new)
      @output = output
      @buffer = []
      @batch_mode = false
      @batch_buffer = nil
      @frame = nil
      @previous_rows = []
      @raw_sequences = []
      @width = 0
      @height = 0
    end

    def start_frame(width:, height:)
      @raw_sequences = []
      @buffer = []

      width_i = width.to_i
      height_i = height.to_i
      width_i = 0 if width_i.negative?
      height_i = 0 if height_i.negative?

      size_changed = (width_i != @width) || (height_i != @height)
      @width = width_i
      @height = height_i
      @previous_rows = Array.new(@height) if size_changed
      @frame = Frame.new(@width, @height)
    end

    def end_frame
      flush_frame
      @output.flush
    end

    def raw(text)
      return unless text

      if @batch_mode
        @batch_buffer << text.to_s
      else
        @raw_sequences << text.to_s
      end
    end

    def write(row, col, text)
      if @frame
        @frame.write(row, col, text)
        return
      end

      content = TerminalOutput::ANSI.move(row, col) + text.to_s
      @output.print(content)
    end

    def write_differential(row, col, text)
      write(row, col, text)
    end

    def clear_buffer_cache
      @previous_rows = Array.new(@height)
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

    private

    def flush_frame
      return unless @frame

      rendered = @frame.rendered_rows
      out = +''
      @raw_sequences.each { |seq| out << seq }

      rendered.each_with_index do |row_text, idx|
        prev = @previous_rows[idx]
        next if prev == row_text

        row_number = idx + 1
        out << TerminalOutput::ANSI.move(row_number, 1)
        out << TerminalOutput::ANSI.clear_line
        out << row_text unless row_text.empty?
        @previous_rows[idx] = row_text
      end

      @output.print(out) unless out.empty?
    ensure
      @frame = nil
      @raw_sequences = []
    end
  end
end
