# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Internal
        # Builds dynamic pagination page data for all chapters.
        # Produces the same page hashes used by PageCalculatorService.
        # Not DI-registered; used internally by the facade service.
        class DynamicPageMapBuilder
          def self.build(doc, col_width, lines_per_page)
            pages_data = []
            total = doc.chapter_count

            total.times do |chapter_idx|
              chapter = doc.get_chapter(chapter_idx)
              next unless chapter

              raw = chapter.lines || []
              wrapped = wrap_lines(raw, col_width)

              wrapped_size = wrapped.size
              page_count = [(wrapped_size.to_f / [lines_per_page, 1].max).ceil, 1].max
              page_count.times do |page_idx|
                start_line = page_idx * lines_per_page
                end_line = [start_line + lines_per_page - 1, wrapped_size - 1].min
                lines_slice = wrapped[start_line..end_line] || []
                pages_data << {
                  chapter_index: chapter_idx,
                  page_in_chapter: page_idx,
                  total_pages_in_chapter: page_count,
                  start_line: start_line,
                  end_line: end_line,
                  lines: lines_slice,
                }
              end

              yield(chapter_idx + 1, total) if block_given?
            end

            pages_data
          end

          class << self
            private

            def wrap_lines(lines, width)
              return [] if lines.empty? || width <= 0

              wrapped = []
              lines.each do |line|
                if line.length <= width
                  wrapped << line
                else
                  wrapped.concat(wrap_long_line(line, width))
                end
              end
              wrapped
            end

            def wrap_long_line(line, width)
              words = line.split(/\s+/)
              wrapped_lines = []
              current_line = ''
              words.each do |word|
                current_line = append_or_wrap(current_line, word, width, wrapped_lines)
              end
              flush_current(current_line, wrapped_lines)
              wrapped_lines
            end

            def append_or_wrap(current, word, width, buffer)
              if current.empty?
                word
              elsif (current.length + 1 + word.length) <= width
                current + " #{word}"
              else
                buffer << current
                word
              end
            end

            def flush_current(current, buffer)
              buffer << current unless current.empty?
            end
          end
        end
      end
    end
  end
end
