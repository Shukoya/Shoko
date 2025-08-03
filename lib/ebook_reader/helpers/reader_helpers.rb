# frozen_string_literal: true

module EbookReader
  module Helpers
    # Helper methods for Reader
    module ReaderHelpers
      def wrap_lines(lines, width)
        return [] if invalid_wrap_params?(lines, width)

        cached_result = get_cached_wrap(lines, width)
        return cached_result if cached_result

        wrapped = process_lines_for_wrapping(lines, width)
        cache_wrapped_result(lines, width, wrapped)
        wrapped
      end

      private

      def invalid_wrap_params?(lines, width)
        lines.nil? || width < 10
      end

      def get_cached_wrap(lines, width)
        @wrap_cache ||= {}
        key = "#{lines.object_id}_#{width}"
        @wrap_cache[key]
      end

      def process_lines_for_wrapping(lines, width)
        wrapped = []
        lines.each do |line|
          next if line.nil?

          if line.strip.empty?
            wrapped << ''
          else
            wrap_line(line, width, wrapped)
          end
        end
        wrapped
      end

      def cache_wrapped_result(lines, width, wrapped)
        @wrap_cache ||= {}
        key = "#{lines.object_id}_#{width}"
        @wrap_cache[key] = wrapped
      end

      def wrap_line(line, width, wrapped)
        words = line.split(/\s+/)
        current = ''

        words.each do |word|
          current = process_word(word, current, width, wrapped)
        end

        wrapped << current unless current.empty?
      end

      def process_word(word, current, width, wrapped)
        return current if word.nil?

        if current.empty?
          word
        elsif fits_on_current_line?(current, word, width)
          "#{current} #{word}"
        else
          wrapped << current
          word
        end
      end

      def fits_on_current_line?(current, word, width)
        current.length + 1 + word.length <= width
      end
    end
  end
end
