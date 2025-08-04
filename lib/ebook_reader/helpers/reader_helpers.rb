# frozen_string_literal: true

module EbookReader
  module Helpers
    # Helper methods for Reader
    module ReaderHelpers
      WordContext = Struct.new(:word, :current, :width, :wrapped)

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
          context = WordContext.new(word, current, width, wrapped)
          current = process_word(context)
        end

        wrapped << current unless current.empty?
      end

      def process_word(context)
        return context.current if context.word.nil?

        return context.word if context.current.empty?

        if word_fits_on_line?(context)
          append_word_to_line(context)
        else
          wrap_to_next_line(context)
        end
      end

      def word_fits_on_line?(context)
        fits_on_current_line?(context.current, context.word, context.width)
      end

      def append_word_to_line(context)
        "#{context.current} #{context.word}"
      end

      def wrap_to_next_line(context)
        context.wrapped << context.current
        context.word
      end

      def fits_on_current_line?(current, word, width)
        current.length + 1 + word.length <= width
      end
    end
  end
end
