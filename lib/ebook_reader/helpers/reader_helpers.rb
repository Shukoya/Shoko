# frozen_string_literal: true

require_relative '../services/chapter_cache'

module EbookReader
  module Helpers
    # Helper methods for Reader
    module ReaderHelpers
      def wrap_lines(lines, width)
        return [] if lines.nil? || width < 10

        @chapter_cache ||= Services::ChapterCache.new
        chapter_index = @state&.get([:reader, :current_chapter]) || 0
        @chapter_cache.get_wrapped_lines(chapter_index, lines, width)
      end
    end
  end
end
