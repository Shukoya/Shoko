# frozen_string_literal: true

require_relative 'models/page_rendering_context'
require_relative 'builders/page_setup_builder'
require_relative 'reader_display/screen_renderer'
require_relative 'reader_display/content_renderer'
require_relative 'reader_display/column_renderer'

module EbookReader
  # Module containing display-related Reader methods
  module ReaderDisplay
    include ScreenRenderer
    include ContentRenderer
    include ColumnRenderer

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
  end
end
