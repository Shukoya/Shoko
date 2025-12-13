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
          def self.build(doc, col_width, lines_per_page, wrapper: nil, formatter: nil, config: nil)
            pages_data = []
            total = doc.chapter_count

            total.times do |chapter_idx|
              chapter = doc.get_chapter(chapter_idx)
              next unless chapter

              wrapped = wrapped_lines(doc, chapter, chapter_idx, col_width, wrapper, formatter, config)

              pages = paginate_lines(wrapped, lines_per_page)
              page_count = [pages.length, 1].max
              pages.each_with_index do |page, page_idx|
                pages_data << {
                  chapter_index: chapter_idx,
                  page_in_chapter: page_idx,
                  total_pages_in_chapter: page_count,
                  start_line: page[:start_line],
                  end_line: page[:end_line],
                  lines: page[:lines],
                }
              end

              yield(chapter_idx + 1, total) if block_given?
            end

            pages_data
          end

          class << self
            private

            def paginate_lines(lines, lines_per_page)
              per_page = [lines_per_page.to_i, 1].max
              list = Array(lines)
              return [{ start_line: 0, end_line: -1, lines: [] }] if list.empty?

              pages = []
              index = 0

              while index < list.length
                start_line = index
                page_lines = []

                while page_lines.length < per_page && index < list.length
                  group_len = image_group_length(list, index)
                  remaining = per_page - page_lines.length

                  if group_len && group_len > remaining && !page_lines.empty?
                    break
                  end

                  if group_len
                    take = [group_len, remaining].min
                    page_lines.concat(list[index, take])
                    index += take
                  else
                    page_lines << list[index]
                    index += 1
                  end
                end

                pages << {
                  start_line: start_line,
                  end_line: start_line + page_lines.length - 1,
                  lines: page_lines,
                }
              end

              pages
            rescue StandardError
              [{ start_line: 0, end_line: [list.length - 1, -1].max, lines: list }]
            end

            def image_group_length(lines, start_index)
              meta = metadata_for(lines[start_index])
              return nil unless meta
              return nil unless meta[:image_render].is_a?(Hash) || meta['image_render'].is_a?(Hash)

              render_line = meta.key?(:image_render_line) ? meta[:image_render_line] : meta['image_render_line']
              return nil unless render_line == true

              image = meta[:image] || meta['image'] || {}
              src = image[:src] || image['src']
              return nil if src.to_s.empty?

              index = start_index
              while index < lines.length
                cur = metadata_for(lines[index])
                break unless cur
                block_type = cur[:block_type] || cur['block_type']
                break unless block_type == :image || block_type.to_s == 'image'

                cur_image = cur[:image] || cur['image'] || {}
                cur_src = cur_image[:src] || cur_image['src']
                break unless cur_src.to_s == src.to_s

                index += 1
              end

              index - start_index
            rescue StandardError
              nil
            end

            def metadata_for(line)
              return nil unless line.respond_to?(:metadata)

              meta = line.metadata
              meta.is_a?(Hash) ? meta : nil
            rescue StandardError
              nil
            end

            def wrapped_lines(doc, chapter, chapter_idx, width, wrapper, formatter, config)
              return [] if width <= 0 || chapter.nil?

              if formatter
                lines = formatter.wrap_all(doc, chapter_idx, width, config: config)
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
