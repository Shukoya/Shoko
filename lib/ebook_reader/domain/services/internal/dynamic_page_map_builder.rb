# frozen_string_literal: true

require_relative '../../../helpers/text_metrics'

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

              lines.each_with_object([]) do |line, acc|
                next if line.nil?

                if line.strip.empty?
                  acc << ''
                else
                  segments = EbookReader::Helpers::TextMetrics.wrap_plain_text(line, width)
                  acc.concat(segments)
                end
              end
            end
          end
        end
      end
    end
  end
end
