# frozen_string_literal: true

require_relative 'base_service'
require_relative '../../services/chapter_cache'

module EbookReader
  module Domain
    module Services
      # Service responsible for wrapping chapter lines to a column width.
      # Uses the shared ChapterCache to avoid recomputation across frames.
      class WrappingService < BaseService
        def initialize(dependencies)
          super
          @chapter_cache = EbookReader::Services::ChapterCache.new
          @window_cache = Hash.new { |h, k| h[k] = {} }
        end
        # Wrap raw lines for a chapter to the given width.
        # Falls back to a local wrapper if cache is unavailable.
        #
        # @param lines [Array<String>] raw chapter lines
        # @param chapter_index [Integer] chapter index for caching keying
        # @param width [Integer] column width
        # @return [Array<String>] wrapped lines
        def wrap_lines(lines, chapter_index, width)
          return [] if lines.nil? || width.to_i < 10

          cache = begin
            registered?(:chapter_cache) ? resolve(:chapter_cache) : @chapter_cache
          rescue StandardError
            @chapter_cache
          end
          cache.get_wrapped_lines(chapter_index, lines, width)
        end

        # Wrap only a window of text sufficient for immediate display.
        # This avoids wrapping the entire chapter on first render.
        #
        # @param lines [Array<String>] raw chapter lines
        # @param chapter_index [Integer] chapter index (for caching semantics if needed)
        # @param width [Integer] column width
        # @param start [Integer] wrapped-lines start offset
        # @param length [Integer] number of wrapped lines to return
        # @return [Array<String>] slice of wrapped lines covering the requested window
        def wrap_window(lines, chapter_index, width, start, length)
          return [] if lines.nil? || width.to_i <= 0 || length.to_i <= 0

          target_end = [start.to_i, 0].max + length.to_i - 1
          key = "#{chapter_index}_#{width}"
          cached = @window_cache[key][[start.to_i, length.to_i]]
          return cached if cached
          wrapped = []

          lines.each do |line|
            break if wrapped.length >= (target_end + 1)

            next if line.nil?
            if line.strip.empty?
              wrapped << ''
              next
            end

            # incremental wrap
            current = ''
            line.split(/\s+/).each do |word|
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

          start_index = [start.to_i, 0].max
          return [] if start_index >= wrapped.length
          slice = wrapped[start_index, length.to_i] || []
          @window_cache[key][[start.to_i, length.to_i]] = slice
          slice
        end

        def prefetch_windows(lines, chapter_index, width, start, length)
          wrap_window(lines, chapter_index, width, start, length)
        end

        # Clear all cached wrapped lines
        def clear_cache
          @chapter_cache = EbookReader::Services::ChapterCache.new
        end

        # Clear cache entries for a given width
        def clear_cache_for_width(width)
          @chapter_cache.clear_cache_for_width(width)
        end

        protected

        def required_dependencies
          []
        end

        private

        # No-op private helpers retained for compatibility-free interface.
      end
    end
  end
end
