# frozen_string_literal: true

module EbookReader
  module Services
    # Caches wrapped lines for chapters to avoid recomputation
    class ChapterCache
      def initialize
        @wrapped_cache = {}
        @cache_key_memo = {}
      end

      # Get wrapped lines for chapter and width
      # @param chapter_index [Integer]
      # @param lines [Array<String>]
      # @param width [Integer]
      # @return [Array<String>]
      def get_wrapped_lines(chapter_index, lines, width)
        cache_key = generate_cache_key(chapter_index, width)
        if @wrapped_cache[cache_key] && @cache_key_memo[cache_key] == lines.object_id
          return @wrapped_cache[cache_key]
        end

        wrapped = wrap_lines_internal(lines, width)
        @wrapped_cache[cache_key] = wrapped
        @cache_key_memo[cache_key] = lines.object_id
        wrapped
      end

      # Clear cached entries for given width
      def clear_cache_for_width(width)
        @wrapped_cache.delete_if { |key, _| key.end_with?("_#{width}") }
      end

      private

      def generate_cache_key(chapter_index, width)
        "#{chapter_index}_#{width}"
      end

      def wrap_lines_internal(lines, width)
        return [] if lines.nil? || width < 10

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

      def wrap_line(line, width, wrapped)
        words = line.split(/\s+/)
        current = ''
        words.each do |word|
          next if word.nil?

          if current.empty?
            current = word
          elsif current.length + 1 + word.length <= width
            current = "#{current} #{word}"
          else
            wrapped << current
            current = word
          end
        end
        wrapped << current unless current.empty?
      end
    end
  end
end
