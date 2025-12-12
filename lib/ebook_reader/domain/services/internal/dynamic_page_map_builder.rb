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
          def self.build(doc, col_width, lines_per_page, wrapper: nil, formatter: nil)
            pages_data = []
            total = doc.chapter_count

            total.times do |chapter_idx|
              chapter = doc.get_chapter(chapter_idx)
              next unless chapter

              wrapped = wrapped_lines(doc, chapter, chapter_idx, col_width, wrapper, formatter)

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

            def wrapped_lines(doc, chapter, chapter_idx, width, wrapper, formatter)
              return [] if width <= 0 || chapter.nil?

              if formatter
                lines = formatter.wrap_all(doc, chapter_idx, width)
                return lines if lines && !lines.empty?
              end

              if wrapper
                lines = wrapper.wrap_lines(chapter.lines || [], chapter_idx, width)
                return lines if lines && !lines.empty?
              end

              wrap_plain_lines(chapter.lines || [], width)
            end

            def wrap_plain_lines(lines, width)
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
