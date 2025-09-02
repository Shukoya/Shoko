# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Service responsible for wrapping chapter lines to a column width.
      # Uses the shared ChapterCache to avoid recomputation across frames.
      class WrappingService < BaseService
        def initialize(dependencies)
          super
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

          if registered?(:chapter_cache)
            cache = resolve(:chapter_cache)
            return cache.get_wrapped_lines(chapter_index, lines, width)
          end

          # Fallback (should rarely happen): wrap without cache
          wrap_lines_fallback(lines, width)
        end

        protected

        def required_dependencies
          [] # Chapter cache is optional; resolved dynamically if present
        end

        private

        def wrap_lines_fallback(lines, width)
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
end

