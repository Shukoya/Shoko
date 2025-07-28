# frozen_string_literal: true

module EbookReader
  # Calculates dynamic page numbers based on current display format
  # Takes into account terminal size, line spacing, and view mode
  module DynamicPageCalculator
    # Calculate total pages and current page for the entire book
    def calculate_dynamic_pages
      return { current: 0, total: 0 } unless @doc && @config.show_page_numbers

      height, width = Terminal.size
      col_width, content_height = get_layout_metrics(width, height)
      actual_height = adjust_for_line_spacing(content_height)

      return { current: 0, total: 0 } if actual_height <= 0

      # Build page map for entire book if terminal size changed
      build_dynamic_page_map(col_width, actual_height) if size_changed?(width,
                                                                        height) || @dynamic_page_map.nil?

      # Calculate current position in entire book
      current_global_page = calculate_global_page_position(actual_height)

      { current: current_global_page, total: @dynamic_total_pages }
    end

    private

    def build_dynamic_page_map(col_width, lines_per_page)
      @dynamic_page_map = []
      @dynamic_chapter_starts = []
      total_lines = 0

      # Calculate pages for each chapter
      @doc.chapters.each_with_index do |chapter, idx|
        @dynamic_chapter_starts << total_lines

        # Wrap lines for current display width
        wrapped = wrap_lines(chapter.lines || [], col_width)
        chapter_lines = wrapped.size
        chapter_pages = (chapter_lines.to_f / lines_per_page).ceil

        @dynamic_page_map << {
          chapter_index: idx,
          lines: chapter_lines,
          pages: chapter_pages,
          start_line: total_lines,
        }

        total_lines += chapter_lines
      end

      # Calculate total pages for entire book
      @dynamic_total_pages = (total_lines.to_f / lines_per_page).ceil
      @dynamic_total_pages = 1 if @dynamic_total_pages < 1

      # Store for resize detection
      @last_dynamic_width = Terminal.size[1]
      @last_dynamic_height = Terminal.size[0]

      Infrastructure::Logger.debug('Dynamic page map built',
                                   total_pages: @dynamic_total_pages,
                                   total_lines:,
                                   lines_per_page:)
    end

    def calculate_global_page_position(lines_per_page)
      return 1 if @dynamic_page_map.nil? || @dynamic_page_map.empty?

      # Use the single page offset for consistency across view modes
      current_line_offset = @single_page

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
      width != @last_dynamic_width || height != @last_dynamic_height
    end
  end
end
