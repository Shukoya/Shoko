# frozen_string_literal: true

module EbookReader
  class TerminalInput
    # Stateful tokenizer for raw terminal input.
    #
    # Converts a stream of bytes into:
    # - Full CSI sequences (e.g. "\e[1;5D", mouse "\e[<...M")
    # - Full SS3 sequences (e.g. "\eOA")
    # - UTF-8 characters (including multibyte)
    # - A lone ESC ("\e") after a small timeout (to disambiguate from escapes)
    class Decoder
      DEFAULT_ESC_TIMEOUT = 0.05
      DEFAULT_SEQUENCE_TIMEOUT = 0.5

      ESC = 0x1B
      CSI_8BIT = 0x9B
      ST_8BIT = 0x9C
      BEL = 0x07

      def initialize(esc_timeout: DEFAULT_ESC_TIMEOUT, sequence_timeout: DEFAULT_SEQUENCE_TIMEOUT)
        @esc_timeout = normalize_timeout(esc_timeout, DEFAULT_ESC_TIMEOUT)
        @sequence_timeout = normalize_timeout(sequence_timeout, DEFAULT_SEQUENCE_TIMEOUT)
        @buffer = +''.b
        @pending_started_at = nil
      end

      def feed(bytes)
        return if bytes.nil? || bytes.empty?

        chunk = String(bytes).dup
        chunk.force_encoding(Encoding::BINARY)
        @buffer << chunk
      rescue StandardError
        nil
      end

      # Returns the next decoded token, or nil if not enough bytes are available.
      def next_token(now: monotonic_now)
        return nil if @buffer.empty?

        token = parse_token
        return token if token

        register_pending(now)
        return nil if now < pending_deadline(now)

        degrade_pending_token
      end

      # When a partial token is buffered, returns seconds to wait before a token
      # should be emitted even if no further bytes arrive.
      def pending_timeout(now: monotonic_now)
        return nil if @buffer.empty?
        return nil unless @pending_started_at

        remaining = pending_deadline(now) - now
        remaining.positive? ? remaining : 0
      end

      private

      def normalize_timeout(value, default)
        t = value.to_f
        t.positive? ? t : default
      rescue StandardError
        default
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue StandardError
        Time.now.to_f
      end

      def register_pending(now)
        @pending_started_at = now if @pending_started_at.nil?
      end

      def clear_pending
        @pending_started_at = nil
      end

      def pending_deadline(now)
        started = @pending_started_at || now
        if @buffer.bytesize == 1 && @buffer.getbyte(0) == ESC
          started + @esc_timeout
        else
          started + @sequence_timeout
        end
      end

      def parse_token
        first = @buffer.getbyte(0)
        case first
        when ESC
          parse_esc_sequence
        when CSI_8BIT
          parse_csi_8bit_sequence
        else
          parse_utf8_character
        end
      end

      def parse_esc_sequence
        return nil if @buffer.bytesize < 2

        second = @buffer.getbyte(1)

        # Two ESC presses should not collapse into an "Alt" sequence.
        if second == ESC
          consume_bytes(1)
          clear_pending
          return "\e"
        end

        case second
        when 0x5B # '[' CSI
          parse_csi_sequence(prefix_bytes: 2, output_prefix: nil)
        when 0x4F # 'O' SS3
          return nil if @buffer.bytesize < 3

          token = @buffer.byteslice(0, 3)
          consume_bytes(3)
          clear_pending
          token.force_encoding(Encoding::UTF_8)
        when 0x5D # ']' OSC
          parse_string_sequence(start_offset: 2, allow_bel: true, output_prefix: nil)
        when 0x50, 0x58, 0x5E, 0x5F # 'P' DCS, 'X' SOS, '^' PM, '_' APC
          parse_string_sequence(start_offset: 2, allow_bel: false, output_prefix: nil)
        else
          parse_alt_modified_character
        end
      end

      def parse_csi_8bit_sequence
        parse_csi_sequence(prefix_bytes: 1, output_prefix: "\e[")
      end

      def parse_csi_sequence(prefix_bytes:, output_prefix:)
        final_index = find_csi_final(start_offset: prefix_bytes)
        return nil unless final_index

        raw = @buffer.byteslice(0, final_index + 1)
        consume_bytes(final_index + 1)
        clear_pending

        if output_prefix
          remainder = raw.byteslice(prefix_bytes, raw.bytesize - prefix_bytes) || ''.b
          (output_prefix + remainder.force_encoding(Encoding::UTF_8)).freeze
        else
          raw.force_encoding(Encoding::UTF_8)
        end
      end

      def find_csi_final(start_offset:)
        i = start_offset
        while i < @buffer.bytesize
          b = @buffer.getbyte(i)
          return i if b && b >= 0x40 && b <= 0x7E

          i += 1
        end
        nil
      end

      def parse_string_sequence(start_offset:, allow_bel:, output_prefix:)
        end_index = find_string_terminator(start_offset: start_offset, allow_bel: allow_bel)
        return nil unless end_index

        raw = @buffer.byteslice(0, end_index)
        consume_bytes(end_index)
        clear_pending

        if output_prefix
          remainder = raw.byteslice(start_offset, raw.bytesize - start_offset) || ''.b
          (output_prefix + remainder.force_encoding(Encoding::UTF_8)).freeze
        else
          raw.force_encoding(Encoding::UTF_8)
        end
      end

      def find_string_terminator(start_offset:, allow_bel:)
        i = start_offset
        while i < @buffer.bytesize
          b = @buffer.getbyte(i)

          return i + 1 if allow_bel && b == BEL

          return i + 1 if b == ST_8BIT

          return i + 2 if b == ESC && @buffer.getbyte(i + 1) == 0x5C # ESC \

          i += 1
        end
        nil
      end

      def parse_alt_modified_character
        decoded = decode_utf8_at(1)
        return nil unless decoded

        char, consumed = decoded
        consume_bytes(1 + consumed)
        clear_pending

        "\e#{char}"
      end

      def parse_utf8_character
        decoded = decode_utf8_at(0)
        return nil unless decoded

        char, consumed = decoded
        consume_bytes(consumed)
        clear_pending
        char
      end

      def decode_utf8_at(offset)
        b0 = @buffer.getbyte(offset)
        return nil unless b0

        return [@buffer.byteslice(offset, 1).force_encoding(Encoding::UTF_8), 1] if b0 < 0x80

        len = utf8_sequence_length(b0)
        return ["\uFFFD", 1] unless len
        return nil if @buffer.bytesize < offset + len

        bytes = @buffer.byteslice(offset, len)
        return ["\uFFFD", 1] unless valid_utf8_bytes?(bytes)

        char = bytes.dup.force_encoding(Encoding::UTF_8)
        char.valid_encoding? ? [char, len] : ["\uFFFD", 1]
      rescue StandardError
        ["\uFFFD", 1]
      end

      def utf8_sequence_length(lead)
        return 2 if lead.between?(0xC2, 0xDF)
        return 3 if lead.between?(0xE0, 0xEF)
        return 4 if lead.between?(0xF0, 0xF4)

        nil
      end

      def valid_utf8_bytes?(bytes)
        b0 = bytes.getbyte(0)
        case bytes.bytesize
        when 2
          b1 = bytes.getbyte(1)
          b1.between?(0x80, 0xBF)
        when 3
          b1 = bytes.getbyte(1)
          b2 = bytes.getbyte(2)
          return false unless b1.between?(0x80, 0xBF)
          return false unless b2.between?(0x80, 0xBF)

          return false if b0 == 0xE0 && b1 < 0xA0
          return false if b0 == 0xED && b1 > 0x9F

          true
        when 4
          b1 = bytes.getbyte(1)
          b2 = bytes.getbyte(2)
          b3 = bytes.getbyte(3)
          return false unless b1.between?(0x80, 0xBF)
          return false unless b2.between?(0x80, 0xBF)
          return false unless b3.between?(0x80, 0xBF)

          return false if b0 == 0xF0 && b1 < 0x90
          return false if b0 == 0xF4 && b1 > 0x8F

          true
        else
          false
        end
      end

      def degrade_pending_token
        b0 = @buffer.getbyte(0)
        consume_bytes(1)
        clear_pending

        case b0
        when ESC
          "\e"
        when CSI_8BIT
          "\e["
        else
          "\uFFFD"
        end
      end

      def consume_bytes(byte_count)
        return if byte_count.to_i <= 0

        @buffer.slice!(0, byte_count)
        @buffer = +''.b if @buffer.nil?
      rescue StandardError
        @buffer = +''.b
      end
    end
  end
end
