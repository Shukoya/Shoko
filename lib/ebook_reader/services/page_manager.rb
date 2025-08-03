# frozen_string_literal: true

module EbookReader
  module Services
    class PageManager
      attr_reader :pages_data

      def initialize(doc, config)
        @doc = doc
        @config = config
        @pages_data = []
      end

      def build_page_map(terminal_width, terminal_height)
        return unless @config.page_numbering_mode == :dynamic

        @pages_data = []
        layout_metrics = prepare_layout_metrics(terminal_width, terminal_height)
        return if layout_metrics[:lines_per_page] <= 0

        build_all_chapter_pages(layout_metrics)
        @pages_data
      end

      # Retrieve page data for a given global page index. Out-of-range
      # indices return the first or last page so callers always receive a
      # valid result rather than needing to handle nils.
      def get_page(page_index)
        return nil if @pages_data.empty?
        return @pages_data.first if page_index.negative?
        return @pages_data.last if page_index >= @pages_data.size

        @pages_data[page_index]
      end

      # Find the global page index for a chapter and line offset. This
      # method is used by the state service when restoring progress and
      # therefore needs to be publicly accessible.
      def find_page_index(chapter_index, line_offset)
        @pages_data.find_index do |page|
          page[:chapter_index] == chapter_index &&
            line_offset >= page[:start_line] &&
            line_offset <= page[:end_line]
        end || 0
      end

      # Total number of pages currently built in the page map.
      def total_pages
        @pages_data.size
      end

      private

      def prepare_layout_metrics(terminal_width, terminal_height)
        col_width, content_height = calculate_layout_metrics(terminal_width, terminal_height)
        lines_per_page = adjust_for_line_spacing(content_height)

        { col_width: col_width, lines_per_page: lines_per_page }
      end

      def build_all_chapter_pages(layout_metrics)
        @doc.chapters.each_with_index do |chapter, chapter_idx|
          build_chapter_pages(chapter, chapter_idx, layout_metrics)
        end
      end

      def build_chapter_pages(chapter, chapter_idx, layout_metrics)
        wrapped_lines = wrap_chapter_lines(chapter, layout_metrics[:col_width])
        page_count = calculate_page_count(wrapped_lines.size, layout_metrics[:lines_per_page])

        page_count.times do |page_idx|
          add_page_data(wrapped_lines, chapter_idx, page_idx, layout_metrics[:lines_per_page],
                        page_count)
        end
      end

      def calculate_page_count(line_count, lines_per_page)
        count = (line_count.to_f / lines_per_page).ceil
        [count, 1].max
      end

      def add_page_data(wrapped_lines, chapter_idx, page_idx, lines_per_page, page_count)
        start_line = page_idx * lines_per_page
        end_line = [start_line + lines_per_page - 1, wrapped_lines.size - 1].min

        @pages_data << {
          chapter_index: chapter_idx,
          page_in_chapter: page_idx,
          total_pages_in_chapter: page_count,
          start_line: start_line,
          end_line: end_line,
          lines: wrapped_lines[start_line..end_line] || [],
        }
      end

      def calculate_layout_metrics(width, height)
        col_width = if @config.view_mode == :split
                      [(width - 3) / 2, 20].max
                    else
                      (width * 0.9).to_i.clamp(30, 120)
                    end
        content_height = [height - 4, 1].max
        [col_width, content_height]
      end

      def adjust_for_line_spacing(height)
        case @config.line_spacing
        when :relaxed
          [height / 2, 1].max
        when :compact
          height
        else
          [(height * 0.8).to_i, 1].max
        end
      end

      def wrap_chapter_lines(chapter, width)
        return [] unless chapter.lines

        process_chapter_lines(chapter.lines, width)
      end

      def process_chapter_lines(lines, width)
        wrapped = []
        lines.each do |line|
          process_single_line(line, width, wrapped)
        end
        wrapped
      end

      def process_single_line(line, width, wrapped)
        return if line.nil?

        if line.strip.empty?
          wrapped << ''
        else
          wrap_line(line, width, wrapped)
        end
      end

      def wrap_line(line, width, wrapped)
        words = line.split(/\s+/)
        process_words(words, width, wrapped)
      end

      def process_words(words, width, wrapped)
        current = ''

        words.each do |word|
          current = add_word_to_line(word, current, width, wrapped)
        end

        wrapped << current unless current.empty?
      end

      def add_word_to_line(word, current, width, wrapped)
        return current if word.nil?

        if current.empty?
          word
        elsif fits_on_line?(current, word, width)
          "#{current} #{word}"
        else
          wrapped << current
          word
        end
      end

      def fits_on_line?(current, word, width)
        current.length + 1 + word.length <= width
      end
    end
  end
end
