# frozen_string_literal: true

module EbookReader
  # Calculates dynamic page numbers based on current display format
  # Takes into account terminal size, line spacing, and view mode
  module DynamicPageCalculator
    ChapterContext = Struct.new(:chapter, :index, :start_line)
    LayoutConfig = Struct.new(:column_width, :lines_per_page)

    # Calculate total pages and current page for the entire book
    def calculate_dynamic_pages
      return { current: 0, total: 0 } unless @doc && @config.show_page_numbers

      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      actual_height = adjust_for_line_spacing(content_height)

      return { current: 0, total: 0 } if actual_height <= 0

      # Build page map for entire book if terminal size changed
      if size_changed?(width, height) || @dynamic_page_map.nil?
        build_dynamic_page_map(col_width, actual_height)
      end

      # Calculate current position in entire book
      current_global_page = calculate_global_page_position(actual_height)

      { current: current_global_page, total: @dynamic_total_pages }
    end

    private

    def build_dynamic_page_map(col_width, lines_per_page)
      initialize_page_map
      layout_config = LayoutConfig.new(col_width, lines_per_page)
      total_lines = process_all_chapters(layout_config)
      finalize_page_calculations(total_lines, lines_per_page)
      cache_terminal_dimensions
    end

    def initialize_page_map
      @dynamic_page_map = []
      @dynamic_chapter_starts = []
    end

    def process_all_chapters(layout_config)
      total_lines = 0
      @doc.chapter_count.times do |idx|
        chapter = @doc.get_chapter(idx)
        next unless chapter

        @dynamic_chapter_starts << total_lines
        context = ChapterContext.new(chapter, idx, total_lines)
        total_lines += process_single_chapter(context, layout_config)
      end
      total_lines
    end

    def process_single_chapter(context, layout_config)
      wrapped = wrap_lines(context.chapter.lines || [], layout_config.column_width)
      chapter_lines = wrapped.size
      chapter_pages = (chapter_lines.to_f / layout_config.lines_per_page).ceil

      @dynamic_page_map << {
        chapter_index: context.index,
        lines: chapter_lines,
        pages: chapter_pages,
        start_line: context.start_line,
      }

      chapter_lines
    end

    def finalize_page_calculations(total_lines, lines_per_page)
      @dynamic_total_pages = (total_lines.to_f / lines_per_page).ceil
      @dynamic_total_pages = 1 if @dynamic_total_pages < 1

      Infrastructure::Logger.debug('Dynamic page map built',
                                   total_pages: @dynamic_total_pages,
                                   total_lines: total_lines,
                                   lines_per_page: lines_per_page)
    end

    def cache_terminal_dimensions
      @last_dynamic_width, @last_dynamic_height = Terminal.size
    end

    def calculate_global_page_position(lines_per_page)
      return 1 if @dynamic_page_map.nil? || @dynamic_page_map.empty?

      # Get current line offset within chapter
      current_line_offset = @config.view_mode == :split ? @left_page : @single_page

      # Calculate total lines before current chapter
      lines_before = @dynamic_chapter_starts[@current_chapter] || 0

      # Total lines up to current position
      total_lines_read = lines_before + current_line_offset

      # Convert to page number (1-based)
      current_page = (total_lines_read.to_f / lines_per_page).floor + 1

      # Ensure within bounds
      [current_page, @dynamic_total_pages].min
    end

    def size_changed?(width, height)
      changed = width != @last_dynamic_width || height != @last_dynamic_height
      @wrap_cache.clear if changed && defined?(@wrap_cache)
      changed
    end
  end
end
