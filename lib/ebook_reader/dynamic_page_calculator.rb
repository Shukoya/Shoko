# frozen_string_literal: true

module EbookReader
  # Calculates dynamic page numbers based on current display format
  # Takes into account terminal size, line spacing, and view mode
  module DynamicPageCalculator
    ChapterContext = Struct.new(:chapter, :index, :start_line)
    LayoutConfig = Struct.new(:column_width, :lines_per_page)

    # Calculate total pages and current page for the entire book
    def calculate_dynamic_pages
      return { current: 0, total: 0 } unless @doc && @config.get([:config, :show_page_numbers])

      height, width = Terminal.size
      @layout_service ||= Domain::ContainerFactory.create_default_container.resolve(:layout_service)
      col_width, content_height = @layout_service.calculate_metrics(width, height, @config.get([:config, :view_mode]))
      actual_height = @layout_service.adjust_for_line_spacing(content_height, @config.get([:config, :line_spacing]))

      return { current: 0, total: 0 } if actual_height <= 0

      # Build page map for entire book if terminal size changed
      if size_changed?(width, height) || @state.get([:reader, :dynamic_page_map]).nil?
        build_dynamic_page_map(col_width, actual_height)
      end

      # Calculate current position in entire book
      current_global_page = calculate_global_page_position(actual_height)

      { current: current_global_page, total: @state.get([:reader, :dynamic_total_pages]) }
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
      @state.update([:reader, :dynamic_page_map], [])
      @state.update([:reader, :dynamic_chapter_starts], [])
    end

    def process_all_chapters(layout_config)
      total_lines = 0
      @doc.chapter_count.times do |idx|
        chapter = @doc.get_chapter(idx)
        next unless chapter

        starts = @state.get([:reader, :dynamic_chapter_starts]) + [total_lines]
        @state.update([:reader, :dynamic_chapter_starts], starts)
        context = ChapterContext.new(chapter, idx, total_lines)
        total_lines += process_single_chapter(context, layout_config)
      end
      total_lines
    end

    def process_single_chapter(context, layout_config)
      wrapped = wrap_lines(context.chapter.lines || [], layout_config.column_width)
      chapter_lines = wrapped.size
      chapter_pages = (chapter_lines.to_f / layout_config.lines_per_page).ceil

      page_map = @state.get([:reader, :dynamic_page_map]) + [{
        chapter_index: context.index,
        lines: chapter_lines,
        pages: chapter_pages,
        start_line: context.start_line,
      }]
      @state.update([:reader, :dynamic_page_map], page_map)

      chapter_lines
    end

    def finalize_page_calculations(total_lines, lines_per_page)
      @state.update([:reader, :dynamic_total_pages], (total_lines.to_f / lines_per_page).ceil)
      @state.update([:reader, :dynamic_total_pages], 1) if @state.get([:reader, :dynamic_total_pages]) < 1

      Infrastructure::Logger.debug('Dynamic page map built',
                                   total_pages: @state.get([:reader, :dynamic_total_pages]),
                                   total_lines: total_lines,
                                   lines_per_page: lines_per_page)
    end

    def cache_terminal_dimensions
      width, height = Terminal.size
      @state.update([:reader, :last_dynamic_width], width)
      @state.update([:reader, :last_dynamic_height], height)
    end

    def calculate_global_page_position(lines_per_page)
      page_map = @state.get([:reader, :dynamic_page_map])
      return 1 if page_map.nil? || page_map.empty?

      # Get current line offset within chapter
      current_line_offset = @config.get([:config, :view_mode]) == :split ? @state.get([:reader, :left_page]) : @state.get([:reader, :single_page])

      # Calculate total lines before current chapter
      chapter_starts = @state.get([:reader, :dynamic_chapter_starts])
      current_chapter = @state.get([:reader, :current_chapter])
      lines_before = chapter_starts[current_chapter] || 0

      # Total lines up to current position
      total_lines_read = lines_before + current_line_offset

      # Convert to page number (1-based)
      current_page = (total_lines_read.to_f / lines_per_page).floor + 1

      # Ensure within bounds
      [current_page, @state.get([:reader, :dynamic_total_pages])].min
    end

    def size_changed?(width, height)
      changed = width != @state.get([:reader, :last_dynamic_width]) || height != @state.get([:reader, :last_dynamic_height])
      if changed && defined?(@chapter_cache)
        @chapter_cache&.clear_cache_for_width(@state.get([:reader, :last_dynamic_width]))
      end
      changed
    end
  end
end
