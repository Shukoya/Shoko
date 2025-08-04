# frozen_string_literal: true

require_relative 'models/page_rendering_context'
require_relative 'builders/page_setup_builder'
require_relative 'reader_display/screen_renderer'
require_relative 'reader_display/content_renderer'

module EbookReader
  # Module containing display-related Reader methods
  module ReaderDisplay
    include ScreenRenderer
    include ContentRenderer

    LineDrawingContext = Struct.new(
      :lines, :start_offset, :end_offset, :position, :dimensions,
      :actual_height, keyword_init: true
    )

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

    def draw_column(context)
      return if invalid_column_params?(context.lines, context.dimensions.width,
                                       context.dimensions.height)

      render_column_content(context)
      draw_page_number(context) if context.show_page_num
    end

    def render_column_content(context)
      actual_height = calculate_actual_height(context.dimensions.height)
      end_offset = [context.offset + actual_height, context.lines.size].min
      drawing_context = LineDrawingContext.new(
        lines: context.lines,
        start_offset: context.offset,
        end_offset: end_offset,
        position: context.position,
        dimensions: context.dimensions,
        actual_height: actual_height
      )
      draw_lines(drawing_context)
    end

    def draw_lines(context)
      calculate_visible_line_range(context).each_with_index do |line_index, display_index|
        render_single_line(
          line: context.lines[line_index],
          row: context.position.row + display_index,
          col: context.position.col,
          width: context.dimensions.width,
          base_row: context.position.row,
          height: context.dimensions.height
        )
      end
    end

    def calculate_visible_line_range(context)
      context.start_offset...context.end_offset
    end

    def render_single_line(line:, row:, col:, width:, base_row:, height:)
      return if row_exceeds_bounds?(row, base_row, height)

      draw_line(
        DrawingParams.new(
          line: line,
          position: Models::Position.new(row: row, col: col),
          width: width
        )
      )
    end

    def row_exceeds_bounds?(row, base_row, height)
      row >= base_row + height
    end

    def invalid_column_params?(lines, width, height)
      lines.nil? || lines.empty? || width < 10 || height < 1
    end

    def calculate_actual_height(height)
      height
    end

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
      page_num = calculate_current_page_number(context.offset, actual_height)
      total_pages = calculate_total_pages(context.lines.size, actual_height)

      {
        text: "#{page_num}/#{total_pages}",
        row: context.position.row + context.dimensions.height - 1,
      }
    end

    def calculate_current_page_number(offset, height)
      (offset / height) + 1
    end

    def calculate_total_pages(total_lines, height)
      [(total_lines.to_f / height).ceil, 1].max
    end

    def draw_page_text(page_info, context)
      return if page_info[:row] >= Terminal.size[0] - 2

      col = calculate_page_text_column(page_info, context)
      text = formatted_page_text(page_info[:text])
      Terminal.write(page_info[:row], col, text)
    end

    def calculate_page_text_column(page_info, context)
      context.position.col +
        [(context.dimensions.width - page_info[:text].length) / 2, 0].max
    end

    def formatted_page_text(text)
      Terminal::ANSI::DIM + Terminal::ANSI::GRAY + text + Terminal::ANSI::RESET
    end
  end
end
