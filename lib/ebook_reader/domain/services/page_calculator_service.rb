# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Enhanced service for page calculations with full PageManager functionality.
      # Migrated from legacy Services::PageManager with dependency injection.
      class PageCalculatorService < BaseService
        # PageData structure for compatibility with PageManager
        PageData = Struct.new(
          :wrapped_lines, :chapter_idx, :page_idx, :lines_per_page, :page_count,
          keyword_init: true
        )
        private_constant :PageData

        attr_reader :pages_data

        def initialize(dependencies_or_state_store, text_wrapper = nil)
          # Handle both old and new constructor signatures during migration
          if dependencies_or_state_store.respond_to?(:resolve)
            # New DI pattern
            super(dependencies_or_state_store)
            @text_wrapper = DefaultTextWrapper.new
          else
            # Legacy pattern - create minimal dependencies
            @dependencies = nil
            @state_store = dependencies_or_state_store
            @text_wrapper = text_wrapper || DefaultTextWrapper.new
          end

          @cache = {}
          @pages_data = []
        end

        # Build complete page map (PageManager compatibility)
        def build_page_map(terminal_width, terminal_height, doc, config)
          return unless EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(config) == :dynamic

          @pages_data = []
          layout_metrics = prepare_layout_metrics(terminal_width, terminal_height, config)
          return if layout_metrics[:lines_per_page] <= 0

          build_all_chapter_pages(doc, layout_metrics)
          @pages_data
        end

        # Get page data by index (PageManager compatibility)
        def get_page(page_index)
          return nil if @pages_data.empty?
          return @pages_data.first if page_index.negative?
          return @pages_data.last if page_index >= @pages_data.size

          @pages_data[page_index]
        end

        # Find page index for chapter and line offset (PageManager compatibility)
        def find_page_index(chapter_index, line_offset)
          @pages_data.find_index do |page|
            page[:chapter_index] == chapter_index &&
              line_offset >= page[:start_line] &&
              line_offset <= page[:end_line]
          end || 0
        end

        # Total pages built in map (PageManager compatibility)
        def total_pages
          @pages_data.size
        end

        # Calculate total pages for a chapter
        #
        # @param chapter_index [Integer] Chapter index
        # @return [Integer] Number of pages in chapter
        def calculate_pages_for_chapter(chapter_index)
          current_state = @state_store.current_state
          cache_key = build_cache_key(chapter_index, current_state)

          @cache[cache_key] ||= perform_page_calculation(chapter_index, current_state)
        end

        # Calculate page position within chapter
        #
        # @param chapter_index [Integer] Chapter index
        # @param line_offset [Integer] Line offset within chapter
        # @return [Integer] Page number within chapter
        def calculate_page_from_line(_chapter_index, line_offset)
          lines_per_page = calculate_lines_per_page
          return 0 if lines_per_page <= 0

          (line_offset.to_f / lines_per_page).floor
        end

        # Calculate line offset from page number
        #
        # @param chapter_index [Integer] Chapter index
        # @param page_number [Integer] Page number within chapter
        # @return [Integer] Line offset
        def calculate_line_from_page(_chapter_index, page_number)
          lines_per_page = calculate_lines_per_page
          page_number * lines_per_page
        end

        # Calculate total pages across all chapters
        #
        # @param chapter_count [Integer] Total number of chapters
        # @return [Integer] Total pages
        def calculate_total_pages(chapter_count)
          (0...chapter_count).sum { |i| calculate_pages_for_chapter(i) }
        end

        # Calculate global page number
        #
        # @param chapter_index [Integer] Current chapter
        # @param page_within_chapter [Integer] Page within current chapter
        # @param total_chapters [Integer] Total chapters
        # @return [Integer] Global page number
        def calculate_global_page_number(chapter_index, page_within_chapter, _total_chapters)
          pages_before = (0...chapter_index).sum { |i| calculate_pages_for_chapter(i) }
          pages_before + page_within_chapter + 1
        end

        # Clear calculation cache
        def clear_cache
          @cache.clear
        end

        # Clear cache for specific dimensions
        #
        # @param width [Integer] Terminal width
        # @param height [Integer] Terminal height
        def clear_cache_for_dimensions(width, height)
          @cache.delete_if { |key, _| key.include?("#{width}x#{height}") }
        end

        private

        def perform_page_calculation(chapter_index, state)
          lines_per_page = calculate_lines_per_page
          
          File.open('/tmp/nav_debug.log', 'a') do |f|
            f.puts "      perform_calc: ch=#{chapter_index}, lines_per_page=#{lines_per_page}"
          end
          
          return 0 if lines_per_page <= 0

          chapter_lines = get_chapter_lines(chapter_index, state)
          wrapped_lines = @text_wrapper.wrap_chapter_lines(chapter_lines, calculate_column_width)
          result = (wrapped_lines.size.to_f / lines_per_page).ceil
          
          File.open('/tmp/nav_debug.log', 'a') do |f|
            f.puts "      ch_lines=#{chapter_lines&.size || 'nil'}, wrapped=#{wrapped_lines.size}, result=#{result}"
          end

          result
        end

        def calculate_lines_per_page
          state = @state_store.current_state
          terminal_height = state.dig(:ui, :terminal_height) || 24

          # Account for header and footer
          content_height = terminal_height - 3 # header(1) + footer(1) + padding(1)

          # Adjust for line spacing
          line_spacing = state.dig(:config, :line_spacing) || :normal
          case line_spacing
          when :relaxed
            [content_height / 2, 1].max
          else
            content_height
          end
        end

        def calculate_column_width
          state = @state_store.current_state
          terminal_width = state.dig(:ui, :terminal_width) || 80
          view_mode = state.dig(:reader, :view_mode) || :split

          case view_mode
          when :single
            terminal_width - 4 # Account for padding
          when :split
            (terminal_width / 2) - 4 # Two columns with padding
          else
            terminal_width - 4
          end
        end

        def get_chapter_lines(chapter_index, state)
          # Access document through state or dependency container
          doc = @dependencies&.resolve(:document) rescue nil
          return [] unless doc
          
          begin
            chapter = doc.get_chapter(chapter_index)
            chapter_lines = chapter&.dig(:lines) || chapter&.lines || []
            
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "        get_chapter_lines: ch=#{chapter_index}, doc_exists=#{!!doc}, lines_count=#{chapter_lines.size}"
              f.puts "        first_few_lines: #{chapter_lines.first(3).inspect}" if chapter_lines.any?
              f.puts "        total_chapters: #{doc.chapters.size}" if doc.respond_to?(:chapters)
            end
            
            chapter_lines
          rescue => e
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "        ERROR in get_chapter_lines: #{e.class}: #{e.message}"
            end
            []
          end
        end

        def build_cache_key(chapter_index, state)
          width = state.dig(:ui, :terminal_width) || 80
          height = state.dig(:ui, :terminal_height) || 24
          view_mode = state.dig(:reader, :view_mode) || :split
          line_spacing = state.dig(:config, :line_spacing) || :normal

          "#{chapter_index}_#{width}x#{height}_#{view_mode}_#{line_spacing}"
        end

        # PageManager compatibility methods
        def prepare_layout_metrics(terminal_width, terminal_height, config)
          col_width, content_height = calculate_layout_metrics(terminal_width, terminal_height,
                                                               config)
          lines_per_page = adjust_for_line_spacing(content_height, config)

          { col_width: col_width, lines_per_page: lines_per_page }
        end

        def build_all_chapter_pages(doc, layout_metrics)
          doc.chapter_count.times do |chapter_idx|
            chapter = doc.get_chapter(chapter_idx)
            next unless chapter

            build_chapter_pages(chapter, chapter_idx, layout_metrics)
          end
        end

        def build_chapter_pages(chapter, chapter_idx, layout_metrics)
          wrapped_lines = wrap_chapter_lines(chapter, layout_metrics[:col_width])
          create_pages_for_chapter(wrapped_lines, chapter_idx, layout_metrics)
        end

        def calculate_page_count(line_count, lines_per_page)
          count = (line_count.to_f / lines_per_page).ceil
          [count, 1].max
        end

        def create_pages_for_chapter(wrapped_lines, chapter_idx, layout_metrics)
          page_count = calculate_page_count(wrapped_lines.size, layout_metrics[:lines_per_page])
          page_count.times do |page_idx|
            info = { chapter_idx: chapter_idx, page_idx: page_idx,
                     layout_metrics: layout_metrics, page_count: page_count }
            page_data = build_page_data(wrapped_lines, info)
            add_page_data(page_data)
          end
        end

        def build_page_data(wrapped_lines, info)
          PageData.new(
            wrapped_lines: wrapped_lines,
            chapter_idx: info[:chapter_idx],
            page_idx: info[:page_idx],
            lines_per_page: info[:layout_metrics][:lines_per_page],
            page_count: info[:page_count]
          )
        end

        def add_page_data(page_data)
          page_info = build_page_info(page_data)
          @pages_data << page_info
        end

        def build_page_info(page_data)
          line_range = calculate_line_range(page_data)

          {
            chapter_index: page_data.chapter_idx,
            page_in_chapter: page_data.page_idx,
            total_pages_in_chapter: page_data.page_count,
            start_line: line_range.first,
            end_line: line_range.last,
            lines: extract_page_lines(page_data, line_range),
          }
        end

        def calculate_line_range(page_data)
          start_line = page_data.page_idx * page_data.lines_per_page
          end_line = calculate_end_line(start_line, page_data)
          start_line..end_line
        end

        def calculate_end_line(start_line, page_data)
          potential_end = start_line + page_data.lines_per_page - 1
          actual_end = page_data.wrapped_lines.size - 1
          [potential_end, actual_end].min
        end

        def extract_page_lines(page_data, line_range)
          page_data.wrapped_lines[line_range] || []
        end

        def calculate_layout_metrics(width, height, config)
          col_width = if EbookReader::Domain::Selectors::ConfigSelectors.view_mode(config) == :split
                        [(width - 3) / 2, 20].max
                      else
                        (width * 0.9).to_i.clamp(30, 120)
                      end
          content_height = [height - 4, 1].max
          [col_width, content_height]
        end

        def adjust_for_line_spacing(height, config)
          case EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(config)
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
            current = add_word_to_line(WordContext.new(word: word, current: current,
                                                       width: width, wrapped: wrapped))
          end
          wrapped << current unless current.empty?
        end

        WordContext = Struct.new(:word, :current, :width, :wrapped, keyword_init: true)
        private_constant :WordContext

        def add_word_to_line(context)
          return context.current if context.word.nil?
          return context.word if context.current.empty?
          return combined_text(context) if fits_on_line?(context.current, context.word,
                                                         context.width)

          append_current(context)
        end

        def fits_on_line?(current, word, width)
          current.length + 1 + word.length <= width
        end

        def combined_text(context)
          "#{context.current} #{context.word}"
        end

        def append_current(context)
          context.wrapped << context.current
          context.word
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store) if @dependencies
        end
      end

      # Default text wrapping implementation
      class DefaultTextWrapper
        def wrap_chapter_lines(lines, column_width)
          return [] if lines.empty? || column_width <= 0

          wrapped = []
          lines.each do |line|
            if line.length <= column_width
              wrapped << line
            else
              wrapped.concat(wrap_long_line(line, column_width))
            end
          end
          wrapped
        end

        private

        def wrap_long_line(line, width)
          words = line.split(/\s+/)
          wrapped_lines = []
          current_line = ''

          words.each do |word|
            if current_line.empty?
              current_line = word
            elsif "#{current_line} #{word}".length <= width
              current_line += " #{word}"
            else
              wrapped_lines << current_line
              current_line = word
            end
          end

          wrapped_lines << current_line unless current_line.empty?
          wrapped_lines
        end
      end
    end
  end
end
