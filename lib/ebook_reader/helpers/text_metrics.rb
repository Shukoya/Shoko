# frozen_string_literal: true

module EbookReader
  module Helpers
    # Utility helpers for measuring and truncating strings that may
    # include ANSI escape sequences.
    module TextMetrics
      ANSI_REGEX = /\[[0-9;]*[A-Za-z]/
      TOKEN_REGEX = /\[[0-9;]*[A-Za-z]|./m

      module_function

      def visible_length(text)
        text.to_s.gsub(ANSI_REGEX, '').length
      end

      def truncate_to(text, width)
        return '' if width.to_i <= 0

        remaining = width.to_i
        buffer = +''
        text.to_s.scan(TOKEN_REGEX).each do |token|
          if token.start_with?("\e[")
            buffer << token
          elsif remaining.positive?
            buffer << token
            remaining -= 1
          else
            break
          end
        end
        buffer
      end
    end
  end
end
