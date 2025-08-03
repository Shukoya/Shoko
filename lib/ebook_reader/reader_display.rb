# frozen_string_literal: true

require_relative 'models/page_rendering_context'
require_relative 'models/drawing_context'
require_relative 'builders/page_setup_builder'

module EbookReader
  # Module containing display-related Reader methods
  module ReaderDisplay
    HELP_LINES = [
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
    ].freeze

    def draw_screen
      Terminal.start_frame
      height, width = Terminal.size

      refresh_page_map(width, height)

      @renderer.render_header(@doc, width, @config.view_mode, @mode)
      draw_content(height, width)
      draw_footer(height, width)
      draw_message(height, width) if @message

      Terminal.end_frame
    end

    def refresh_page_map(width, height)
      if @config.page_numbering_mode == :dynamic && @page_manager
        if size_changed?(width, height)
          @page_manager.build_page_map(width, height)
          @current_page_index = [@current_page_index, @page_manager.total_pages - 1].min
          @current_page_index = [0, @current_page_index].max
        end
      elsif size_changed?(width, height)
        update_page_map(width, height)
      end
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
      context = Models::FooterRenderingContext.new(height: height, width: width, doc: @doc,
                                                   chapter: @current_chapter, pages: pages,
                                                   view_mode: @config.view_mode, mode: @mode,
                                                   line_spacing: @config.line_spacing,
                                                   bookmarks: @bookmarks)
      @renderer.render_footer(context)
    end

    def calculate_current_pages
      return { current: 0, total: 0 } unless @config.show_page_numbers

      if @config.page_numbering_mode == :dynamic
        dynamic_page_numbers
      else
        absolute_page_numbers
      end
    end

    def dynamic_page_numbers
      return { current: 0, total: 0 } unless @page_manager

      {
        current: @current_page_index + 1,
        total: @page_manager.total_pages,
      }
    end

    def absolute_page_numbers
      height, width = Terminal.size
      _, content_height = get_layout_metrics(width, height)
      actual_height = adjust_for_line_spacing(content_height)

      return { current: 0, total: 0 } if invalid_page_calculation?(actual_height, width, height)

      calculate_global_page_position(actual_height)
    end

    def invalid_page_calculation?(actual_height, width, height)
      return true if actual_height <= 0

      update_page_map(width, height) if size_changed?(width, height) || @page_map.empty?
      !@total_pages.positive?
    end

    def calculate_global_page_position(actual_height)
      pages_before = @page_map[0...@current_chapter].sum
      line_offset = @config.view_mode == :split ? @left_page : @single_page
      page_in_chapter = (line_offset.to_f / actual_height).floor + 1
      current_global_page = pages_before + page_in_chapter

      { current: current_global_page, total: @total_pages }
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
      left_context = Models::PageRenderingContext.new(
        lines: wrapped,
        offset: @left_page,
        dimensions: Models::Dimensions.new(width: col_width, height: content_height),
        position: Models::Position.new(row: 3, col: 1),
        show_page_num: true
      )
      draw_column(left_context)

      draw_divider(height, col_width)

      right_context = Models::PageRenderingContext.new(
        lines: wrapped,
        offset: @right_page,
        dimensions: Models::Dimensions.new(width: col_width, height: content_height),
        position: Models::Position.new(row: 3, col: col_width + 5),
        show_page_num: false
      )
      draw_column(right_context)
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

      setup = calculate_dynamic_screen_setup(width, height, page_data)
      draw_dynamic_lines(page_data[:lines], setup)
    end

    def calculate_dynamic_screen_setup(width, height, page_data)
      col_width, content_height = get_layout_metrics(width, height)
      col_start = calculate_column_start(width, col_width)

      start_row = calculate_start_row(content_height, page_data[:lines])

      { col_start: col_start, col_width: col_width, start_row: start_row, height: height }
    end

    def calculate_column_start(width, col_width)
      [(width - col_width) / 2, 1].max
    end

    def calculate_start_row(content_height, lines)
      actual_lines = calculate_actual_line_count(lines)
      padding = [(content_height - actual_lines) / 2, 0].max
      [3 + padding, 3].max
    end

    def calculate_actual_line_count(lines)
      if @config.line_spacing == :relaxed
        [(lines.size * 2) - 1, 0].max
      else
        lines.size
      end
    end

    def draw_dynamic_lines(lines, setup)
      lines.each_with_index do |line, idx|
        row = calculate_line_row(setup[:start_row], idx)
        break if row >= setup[:height] - 2

        draw_line(
          DrawingParams.new(
            line: line,
            position: Models::Position.new(row: row, col: setup[:col_start]),
            width: setup[:col_width]
          )
        )
      end
    end

    def calculate_line_row(start_row, index)
      start_row + if @config.line_spacing == :relaxed
                    index * 2
                  else
                    index
                  end
    end

    def draw_single_screen_absolute(height, width)
      chapter = @doc.get_chapter(@current_chapter)
      return unless chapter

      setup = prepare_absolute_screen_setup(chapter, width, height)
      draw_absolute_content(setup)
    end

    def prepare_absolute_screen_setup(chapter, width, height)
      col_width, content_height = get_layout_metrics(width, height)
      col_start = calculate_column_start(width, col_width)
      displayable_lines = adjust_for_line_spacing(content_height)
      wrapped = wrap_lines(chapter.lines || [], col_width)
      lines_in_page = extract_lines_in_page(wrapped, displayable_lines)
      build_setup_hash(lines_in_page, wrapped, col_width, col_start, content_height,
                       displayable_lines)
    end

    def build_setup_hash(lines, wrapped, col_width, col_start, content_height, displayable)
      Builders::PageSetupBuilder.new
                                .with_lines(lines)
                                .with_wrapped(wrapped)
                                .with_dimensions(col_width, content_height, displayable)
                                .with_position(col_start)
                                .build
    end

    def extract_lines_in_page(wrapped, displayable_lines)
      wrapped.slice(@single_page, displayable_lines) || []
    end

    def draw_absolute_content(setup)
      actual_lines = calculate_actual_line_count(setup[:lines])
      padding = setup[:content_height] - actual_lines
      start_row = [3 + (padding / 2), 3].max

      params = build_single_screen_params(setup, start_row)
      draw_column(params)
    end

    def build_single_screen_params(setup, start_row)
      Models::PageRenderingContext.new(
        lines: setup[:wrapped],
        offset: @single_page,
        dimensions: Models::Dimensions.new(width: setup[:col_width],
                                           height: setup[:displayable_lines]),
        position: Models::Position.new(row: start_row, col: setup[:col_start]),
        show_page_num: false
      )
    end

    def draw_column(context)
      return if invalid_column_params?(context.lines, context.dimensions.width,
                                       context.dimensions.height)

      actual_height = calculate_actual_height(context.dimensions.height)
      end_offset = [context.offset + actual_height, context.lines.size].min
      draw_lines(LineDrawingContext.new(lines: context.lines, start_offset: context.offset,
                                        end_offset: end_offset, position: context.position,
                                        dimensions: context.dimensions,
                                        actual_height: actual_height))
      return unless context.show_page_num

      draw_page_number(context)
    end

    def invalid_column_params?(lines, width, height)
      lines.nil? || lines.empty? || width < 10 || height < 1
    end

    def calculate_actual_height(height)
      height
    end

    LineDrawingContext = Struct.new(
      :lines, :start_offset, :end_offset, :position, :dimensions, :actual_height,
      keyword_init: true
    )

    def draw_lines(context)
      line_count = 0
      (context.start_offset...context.end_offset).each do |line_idx|
        break if line_count >= context.actual_height

        line = context.lines[line_idx] || ''
        line_context = LineContext.new(line: line, position: context.position,
                                       width: context.dimensions.width,
                                       line_count: line_count)
        line_count = draw_spaced_line(line_context)
      end
    end

    def draw_spaced_line(context)
      row = calculate_row(context.position.row, context.line_count)
      return context.line_count + 1 if row >= Terminal.size[0] - 2

      draw_line(DrawingParams.new(line: context.line, position: context.position,
                                  width: context.width))
      context.line_count + 1
    end

    LineContext = Struct.new(:line, :position, :width, :line_count, keyword_init: true)
    DrawingParams = Struct.new(:line, :position, :width, keyword_init: true)

    def calculate_row(start_row, line_count)
      start_row + if @config.line_spacing == :relaxed
                    line_count * 2
                  else
                    line_count
                  end
    end

    def draw_line(params)
      if should_highlight_line?(params.line)
        draw_highlighted_line(params)
      else
        Terminal.write(params.position.row, params.position.col,
                       Terminal::ANSI::WHITE + params.line[0, params.width] +
                       Terminal::ANSI::RESET)
      end
    end

    def should_highlight_line?(line)
      return false unless @config.highlight_quotes

      pattern = Regexp.union(Constants::QUOTE_PATTERNS, Constants::HIGHLIGHT_PATTERNS)
      line.match?(pattern)
    end

    def draw_highlighted_line(params)
      display_line = highlight_keywords(params.line)
      display_line = highlight_quotes(display_line)
      Terminal.write(params.position.row, params.position.col,
                     Terminal::ANSI::WHITE + display_line[0, params.width] +
                     Terminal::ANSI::RESET)
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

    def draw_page_number(context)
      return unless should_draw_page_number?(context)

      page_info = calculate_page_info(context)
      draw_page_text(page_info, context)
    end

    def should_draw_page_number?(context)
      @config.show_page_numbers &&
        context.lines&.size&.positive? &&
        calculate_actual_height(context.dimensions.height).positive?
    end

    def calculate_page_info(context)
      actual_height = calculate_actual_height(context.dimensions.height)
      page_num = (context.offset / actual_height) + 1
      total_pages = [(context.lines.size.to_f / actual_height).ceil, 1].max

      {
        text: "#{page_num}/#{total_pages}",
        row: context.position.row + context.dimensions.height - 1,
      }
    end

    def draw_page_text(page_info, context)
      return if page_info[:row] >= Terminal.size[0] - 2

      col = context.position.col +
            [(context.dimensions.width - page_info[:text].length) / 2, 0].max
      Terminal.write(page_info[:row], col,
                     Terminal::ANSI::DIM + Terminal::ANSI::GRAY + page_info[:text] +
                     Terminal::ANSI::RESET)
    end

    def draw_help_screen(height, width)
      start_row = [(height - HELP_LINES.size) / 2, 1].max

      HELP_LINES.each_with_index do |line, idx|
        row = start_row + idx
        break if row >= height - 2

        draw_help_line(line, row, width)
      end
    end

    def draw_help_line(line, row, width)
      col = [(width - line.length) / 2, 1].max
      Terminal.write(row, col, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
    end

    def build_help_lines
      HELP_LINES
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
        draw_toc_line(idx, line, list_start + row, width)
      end
    end

    def draw_toc_line(idx, line, row, width)
      if idx == @toc_selected
        Terminal.write(row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
        Terminal.write(row, 4,
                       Terminal::ANSI::BRIGHT_WHITE + line[0, width - 6] + Terminal::ANSI::RESET)
      else
        Terminal.write(row, 4, Terminal::ANSI::WHITE + line[0, width - 6] + Terminal::ANSI::RESET)
      end
    end

    def draw_toc_footer(height)
      Terminal.write(height - 1, 2,
                     "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • t/ESC Back#{Terminal::ANSI::RESET}")
    end
  end
end
