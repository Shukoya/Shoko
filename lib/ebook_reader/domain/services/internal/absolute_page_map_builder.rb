# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Internal
        # Small helper to compute absolute page maps per chapter.
        # Encapsulates the per-chapter wrapping + page counting loop.
        class AbsolutePageMapBuilder
          def self.build(doc, col_width, lines_per_page, wrapper = nil)
            total = doc.chapter_count
            page_map = []
            total.times do |i|
              chapter = doc.get_chapter(i)
              lines = chapter&.lines || []

              wrapped = if wrapper
                          wrapper.wrap_lines(lines, i, col_width)
                        else
                          EbookReader::Domain::Services::DefaultTextWrapper.new.wrap_chapter_lines(lines, col_width)
                        end

              pages = (wrapped.size.to_f / [lines_per_page, 1].max).ceil
              page_map << pages
              yield(i + 1, total) if block_given?
            end
            page_map
          end
        end
      end
    end
  end
end

