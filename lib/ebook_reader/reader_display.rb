# frozen_string_literal: true

module EbookReader
  # Module containing display-related Reader methods
  module ReaderDisplay
    def draw_screen
      Terminal.start_frame
      height, width = Terminal.size

      if @config.page_numbering_mode == :dynamic && @page_manager
        if size_changed?(width, height)
          @page_manager.build_page_map(width, height)
          @current_page_index = [@current_page_index, @page_manager.total_pages - 1].min
          @current_page_index = [0, @current_page_index].max
        end
      elsif size_changed?(width, height)
        update_page_map(width, height)
      end

      @renderer.render_header(@doc, width, @config.view_mode, @mode)
      draw_content(height, width)
      draw_footer(height, width)
      draw_message(height, width) if @message

      Terminal.end_frame
    end

    def size_changed?(width, height)
      changed = width != @last_width || height != @last_height
      @wrap_cache.clear if changed && defined?(@wrap_cache)
      changed
    end

    def draw_content(height, width)
      case @mode
      when :help then draw_help_screen(height, width)
      when :toc then draw_toc_screen(height, width)
      when :bookmarks then draw_bookmarks_screen(height, width)
      else draw_reading_content(height, width)
      end
    end

    def draw_reading_content(height, width)
      if @config.view_mode == :split
        draw_split_screen(height, width)
      else
        draw_single_screen(height, width)
      end
    end

    def draw_footer(height, width)
      pages = calculate_current_pages
      @renderer.render_footer(height, width, @doc, @current_chapter, pages,
                              @config.view_mode, @mode, @config.line_spacing, @bookmarks)
    end

    def calculate_current_pages
      return { current: 0, total: 0 } unless @config.show_page_numbers

      if @config.page_numbering_mode == :dynamic
        return { current: 0, total: 0 } unless @page_manager

        {
          current: @current_page_index + 1,
          total: @page_manager.total_pages,
        }
      else
        height, width = Terminal.size
        _, content_height = get_layout_metrics(width, height)
        actual_height = adjust_for_line_spacing(content_height)
        return { current: 0, total: 0 } if actual_height <= 0

        update_page_map(width, height) if size_changed?(width, height) || @page_map.empty?
        return { current: 0, total: 0 } unless @total_pages.positive?

        pages_before = @page_map[0...@current_chapter].sum
        line_offset = @config.view_mode == :split ? @left_page : @single_page
        page_in_chapter = (line_offset.to_f / actual_height).floor + 1
        current_global_page = pages_before + page_in_chapter

        { current: current_global_page, total: @total_pages }
      end
    end

    def draw_message(height, width)
      msg_len = @message.length
      Terminal.write(height / 2, (width - msg_len) / 2,
                     "#{Terminal::ANSI::BG_DARK}#{Terminal::ANSI::BRIGHT_YELLOW} #{@message} " \
                     "#{Terminal::ANSI::RESET}")
    end

    def draw_split_screen(height, width)
      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      col_width, content_height = get_layout_metrics(width, height)
      content_height = adjust_for_line_spacing(content_height)
      wrapped = wrap_lines(chapter.lines || [], col_width)

      draw_chapter_info(chapter, width)
      draw_split_columns(wrapped, col_width, content_height, height)
    end

    def draw_chapter_info(chapter, width)
      chapter_info = "[#{@current_chapter + 1}] #{chapter.title || 'Unknown'}"
      Terminal.write(2, 1, Terminal::ANSI::BLUE + chapter_info[0, width - 2] + Terminal::ANSI::RESET)
    end

    def draw_split_columns(wrapped, col_width, content_height, height)
      left_params = Models::ColumnDrawingParams.new(
        position: Models::ColumnDrawingParams::Position.new(row: 3, col: 1),
        dimensions: Models::ColumnDrawingParams::Dimensions.new(width: col_width,
                                                                height: content_height),
        content: Models::ColumnDrawingParams::Content.new(lines: wrapped, offset: @left_page,
                                                          show_page_num: true)
      )
      draw_column(left_params)
      draw_divider(height, col_width)
      right_params = Models::ColumnDrawingParams.new(
        position: Models::ColumnDrawingParams::Position.new(row: 3, col: col_width + 5),
        dimensions: Models::ColumnDrawingParams::Dimensions.new(width: col_width,
                                                                height: content_height),
        content: Models::ColumnDrawingParams::Content.new(lines: wrapped, offset: @right_page,
                                                          show_page_num: false)
      )
      draw_column(right_params)
    end

    def draw_divider(height, col_width)
      (3...[height - 1, 4].max).each do |row|
        Terminal.write(row, col_width + 3, "#{Terminal::ANSI::GRAY}│#{Terminal::ANSI::RESET}")
      end
    end

    def draw_single_screen(height, width)
      if @config.page_numbering_mode == :dynamic
        draw_single_screen_dynamic(height, width)
      else
        draw_single_screen_absolute(height, width)
      end
    end

    private

    def draw_single_screen_dynamic(height, width)
      return unless @page_manager

      page_data = @page_manager.get_page(@current_page_index)
      return unless page_data

      col_width, content_height = get_layout_metrics(width, height)
      col_start = [(width - col_width) / 2, 1].max
      lines_to_display = page_data[:lines]

      actual_lines = if @config.line_spacing == :relaxed
                       [(lines_to_display.size * 2) - 1, 0].max
                     else
                       lines_to_display.size
                     end

      padding = [(content_height - actual_lines) / 2, 0].max
      start_row = [3 + padding, 3].max

      lines_to_display.each_with_index do |line, idx|
        row = start_row + if @config.line_spacing == :relaxed
                            idx * 2
                          else
                            idx
                          end
        break if row >= height - 2

        draw_line(line, row, col_start, col_width)
      end
    end

    def draw_single_screen_absolute(height, width)
      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      col_width, content_height = get_layout_metrics(width, height)
      col_start = [(width - col_width) / 2, 1].max
      displayable_lines = adjust_for_line_spacing(content_height)
      wrapped = wrap_lines(chapter.lines || [], col_width)

      lines_in_page = wrapped.slice(@single_page, displayable_lines) || []

      actual_lines = if @config.line_spacing == :relaxed
                       [(lines_in_page.size * 2) - 1, 0].max
                     else
                       lines_in_page.size
                     end

      padding = content_height - actual_lines
      start_row = [3 + (padding / 2), 3].max

      params = Models::ColumnDrawingParams.new(
        position: Models::ColumnDrawingParams::Position.new(row: start_row, col: col_start),
        dimensions: Models::ColumnDrawingParams::Dimensions.new(width: col_width,
                                                                height: displayable_lines),
        content: Models::ColumnDrawingParams::Content.new(lines: wrapped, offset: @single_page,
                                                          show_page_num: false)
      )
      draw_column(params)
    end

    def draw_column(params)
      lines = params.content.lines
      width = params.dimensions.width
      height = params.dimensions.height
      return if invalid_column_params?(lines, width, height)

      actual_height = calculate_actual_height(height)
      end_offset = [params.content.offset + actual_height, lines.size].min

      draw_lines(lines, params.content.offset, end_offset, params.position.row,
                 params.position.col, width, actual_height)
      return unless params.content.show_page_num

      draw_page_number(params)
    end

    def invalid_column_params?(lines, width, height)
      lines.nil? || lines.empty? || width < 10 || height < 1
    end

    def calculate_actual_height(height)
      height
    end

    def draw_lines(lines, start_offset, end_offset, start_row, start_col, width, actual_height)
      line_count = 0
      (start_offset...end_offset).each do |line_idx|
        break if line_count >= actual_height

        line = lines[line_idx] || ''
        row = start_row + if @config.line_spacing == :relaxed
                            line_count * 2
                          else
                            line_count
                          end

        next if row >= Terminal.size[0] - 2

        draw_line(line, row, start_col, width)
        line_count += 1
      end
    end

    def draw_line(line, row, start_col, width)
      if should_highlight_line?(line)
        draw_highlighted_line(line, row, start_col, width)
      else
        Terminal.write(row, start_col, Terminal::ANSI::WHITE + line[0, width] + Terminal::ANSI::RESET)
      end
    end

    def should_highlight_line?(line)
      return false unless @config.highlight_quotes

      pattern = Regexp.union(Constants::QUOTE_PATTERNS, Constants::HIGHLIGHT_PATTERNS)
      line.match?(pattern)
    end

    def draw_highlighted_line(line, row, start_col, width)
      display_line = highlight_keywords(line)
      display_line = highlight_quotes(display_line)
      Terminal.write(row, start_col, Terminal::ANSI::WHITE + display_line[0, width] + Terminal::ANSI::RESET)
    end

    def highlight_keywords(line)
      line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
        Terminal::ANSI::CYAN + match + Terminal::ANSI::WHITE
      end
    end

    def highlight_quotes(line)
      line.gsub(Constants::QUOTE_PATTERNS) do |match|
        Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + Terminal::ANSI::WHITE
      end
    end

    def draw_page_number(params)
      lines = params.content.lines
      width = params.dimensions.width
      height = params.dimensions.height
      offset = params.content.offset
      actual_height = calculate_actual_height(height)
      return unless @config.show_page_numbers && lines.size.positive? && actual_height.positive?

      page_num = (offset / actual_height) + 1
      total_pages = [(lines.size.to_f / actual_height).ceil, 1].max
      page_text = "#{page_num}/#{total_pages}"
      page_row = params.position.row + height - 1

      return if page_row >= Terminal.size[0] - 2

      col = params.position.col + [(width - page_text.length) / 2, 0].max
      Terminal.write(page_row, col,
                     Terminal::ANSI::DIM + Terminal::ANSI::GRAY + page_text + Terminal::ANSI::RESET)
    end

    def draw_help_screen(height, width)
      help_lines = build_help_lines
      start_row = [(height - help_lines.size) / 2, 1].max

      help_lines.each_with_index do |line, idx|
        row = start_row + idx
        break if row >= height - 2

        col = [(width - line.length) / 2, 1].max
        Terminal.write(row, col, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
      end
    end

    def build_help_lines
      [
        '',
        'Navigation Keys:',
        '  j / ↓     Scroll down',
        '  k / ↑     Scroll up',
        '  l / →     Next page',
        '  h / ←     Previous page',
        '  SPACE     Next page',
        '  n         Next chapter',
        '  p         Previous chapter',
        '  g         Go to beginning of chapter',
        '  G         Go to end of chapter',
        '',
        'View Options:',
        '  v         Toggle split/single view',
        '  P         Toggle page numbering mode (Absolute/Dynamic)',
        '  + / -     Adjust line spacing',
        '',
        # Copy mode was removed; pages are always printed so terminals can select text.
        'Features:',
        '  t         Show Table of Contents',
        '  b         Add a bookmark',
        '  B         Show bookmarks',
        '',
        'Other Keys:',
        '  ?         Show/hide this help',
        '  q         Quit to menu',
        '  Q         Quit application',
        '',
        '',
        'Press any key to return to reading...',
      ]
    end

    def draw_toc_screen(height, width)
      draw_toc_header(width)
      draw_toc_list(height, width)
      draw_toc_footer(height)
    end

    def draw_toc_header(width)
      Terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}📖 Table of Contents#{Terminal::ANSI::RESET}")
      Terminal.write(1, [width - 30, 40].max,
                     "#{Terminal::ANSI::DIM}[t/ESC] Back to Reading#{Terminal::ANSI::RESET}")
    end

    def draw_toc_list(height, width)
      list_start = 4
      list_height = height - 6
      chapters = @doc.chapters
      return if chapters.empty?

      visible_range = calculate_toc_visible_range(list_height, chapters.length)
      draw_toc_items(visible_range, chapters, list_start, width)
    end

    def calculate_toc_visible_range(list_height, chapter_count)
      visible_start = [@toc_selected - (list_height / 2), 0].max
      visible_end = [visible_start + list_height, chapter_count].min
      visible_start...visible_end
    end

    def draw_toc_items(range, chapters, list_start, width)
      range.each_with_index do |idx, row|
        chapter = chapters[idx]
        line = chapter.title || 'Untitled'

        if idx == @toc_selected
          Terminal.write(list_start + row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
          Terminal.write(list_start + row, 4,
                         Terminal::ANSI::BRIGHT_WHITE + line[0, width - 6] + Terminal::ANSI::RESET)
        else
          Terminal.write(list_start + row, 4, Terminal::ANSI::WHITE + line[0, width - 6] + Terminal::ANSI::RESET)
        end
      end
    end

    def draw_toc_footer(height)
      Terminal.write(height - 1, 2,
                     "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{Terminal::ANSI::RESET}")
    end

  end
end
