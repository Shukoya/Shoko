# frozen_string_literal: true

require_relative 'base_service'
require_relative 'internal/chapter_cache'

module EbookReader
  module Domain
    module Services
      # Service responsible for wrapping chapter lines to a column width.
      # Uses the shared ChapterCache to avoid recomputation across frames.
      class WrappingService < BaseService
        WINDOW_CACHE_LIMIT = 200
        def initialize(dependencies)
          super
          @chapter_cache = EbookReader::Domain::Services::Internal::ChapterCache.new
          @window_cache = Hash.new { |h, k| h[k] = { store: {}, order: [] } }
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
          width_i = width.to_i
          length_i = length.to_i
          start_i = start.to_i
          return [] if lines.nil? || width_i <= 0 || length_i <= 0

          target_end = [start_i, 0].max + length_i - 1
          key = "#{chapter_index}_#{width_i}"
          cached = @window_cache[key][:store][[start_i, length_i]]
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
              elsif current.length + 1 + word.length <= width_i
                current = "#{current} #{word}"
              else
                wrapped << current
                current = word
              end
            end
            wrapped << current unless current.empty?
          end

          start_index = [start_i, 0].max
          return [] if start_index >= wrapped.length

          slice = wrapped[start_index, length_i] || []
          cache_put(key, [start_i, length_i], slice)
          slice
        end

        def prefetch_windows(lines, chapter_index, width, start, length)
          wrap_window(lines, chapter_index, width, start, length)
        end

        # Wrap the visible window and prefetch ±N pages around it in the background.
        # This centralizes the behavior that was previously embedded in ReaderController.
        #
        # @param doc [Object] document responding to #get_chapter(index)
        # @param chapter_index [Integer]
        # @param col_width [Integer]
        # @param offset [Integer] wrapped-line offset
        # @param display_height [Integer] lines per page
        # @param pre_pages [Integer,nil] optional number of pages to prefetch; defaults from config
        # @return [Array<String>] visible wrapped lines for the requested window
        def fetch_window_and_prefetch(doc, chapter_index, col_width, offset, display_height,
                                      pre_pages = nil)
          return [] unless doc && display_height.to_i.positive?

          chapter = doc.get_chapter(chapter_index)
          return [] unless chapter

          lines = chapter.lines || []
          start_i = [offset.to_i, 0].max
          length_i = display_height.to_i

          visible = wrap_window(lines, chapter_index, col_width, start_i, length_i)

          begin
            pages = pre_pages
            if pages.nil?
              st = resolve(:state_store) if registered?(:state_store)
              pages = begin
                (st&.dig(:config,
                         :prefetch_pages) || st&.get(%i[config prefetch_pages]) || 20).to_i
              rescue StandardError
                20
              end
            end
            pages = pages.clamp(0, 200)
            window = pages * length_i
            prefetch_start = [start_i - window, 0].max
            prefetch_end   = start_i + window + (length_i - 1)
            prefetch_len   = prefetch_end - prefetch_start + 1
            Thread.new do
              prefetch_windows(lines, chapter_index, col_width, prefetch_start, prefetch_len)
            rescue StandardError
              # ignore background failures
            end
          rescue StandardError
            # best-effort prefetch
          end

          visible
        end

        # Clear all cached wrapped lines
        def clear_cache
          @chapter_cache = EbookReader::Domain::Services::Internal::ChapterCache.new
          @window_cache.clear
        end

        # Clear cache entries for a given width
        def clear_cache_for_width(width)
          @chapter_cache.clear_cache_for_width(width)
          @window_cache.delete_if { |k, _| k.end_with?("_#{width}") }
        end

        protected

        def required_dependencies
          []
        end

        private

        # No-op private helpers retained for compatibility-free interface.

        def cache_put(key, subkey, value)
          entry = @window_cache[key]
          store = entry[:store]
          order = entry[:order]
          unless store.key?(subkey)
            order << subkey
            if order.length > WINDOW_CACHE_LIMIT
              oldest = order.shift
              store.delete(oldest)
            end
          end
          store[subkey] = value
        end
      end
    end
  end
end
