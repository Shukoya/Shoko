# frozen_string_literal: true

module EbookReader
  module Terminal
    class << self
      # Enable mouse tracking
      def enable_mouse
        print "\e[?1003h\e[?1006h" # Enable mouse tracking with SGR encoding
        $stdout.flush
      end

      # Disable mouse tracking
      def disable_mouse
        print "\e[?1003l\e[?1006l" # Disable mouse tracking
        $stdout.flush
      end

      # Read mouse or keyboard input
      def read_input_with_mouse
        input = read_key_blocking
        return nil unless input

        # Check if it's a mouse event
        if input.start_with?("\e[<")
          # Continue reading the rest of the mouse sequence
          while input[-1] != 'm' && input[-1] != 'M'
            extra = read_key
            break unless extra
            input += extra
          end
        end

        input
      end
    end
  end
end
