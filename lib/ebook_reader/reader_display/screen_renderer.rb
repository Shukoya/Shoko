# frozen_string_literal: true

module EbookReader
  module ReaderDisplay
    # Handles rendering of main reading screens
    module ScreenRenderer
      SplitColumnDrawingContext = Struct.new(
        :wrapped_lines, :col_width, :content_height,
        :total_height, :left_page_offset, :right_page_offset
      )

      PageSetupBuildContext = Struct.new(
        :lines, :wrapped, :col_width, :col_start, :content_height,
        :displayable_lines
      )

      def draw_reading_content(height, width)
        if @config.view_mode == :split
          draw_split_screen(height, width)
        else
          draw_single_screen(height, width)
        end
      end

      def draw_split_screen(height, width)
        chapter = @doc.get_chapter(@state.current_chapter)
        return unless chapter

        col_width, content_height = get_layout_metrics(width, height)
        content_height = adjust_for_line_spacing(content_height)
        wrapped = wrap_lines(chapter.lines || [], col_width)

        draw_chapter_info(chapter, width)
        context = SplitColumnDrawingContext.new(
          wrapped, col_width, content_height, height,
          @state.left_page, @state.right_page
        )
        draw_split_columns(context)
      end

      def draw_chapter_info(chapter, width)
        chapter_info = "[#{@state.current_chapter + 1}] #{chapter.title || 'Unknown'}"
        Terminal.write(2, 1, Terminal::ANSI::BLUE + chapter_info[0, width - 2] + Terminal::ANSI::RESET)
      end

      def draw_split_columns(context)
        draw_left_column_content(context)
        draw_column_divider(context)
        draw_right_column_content(context)
      end

      private

      def draw_left_column_content(context)
        left_context = build_column_context(
          lines: context.wrapped_lines,
          offset: context.left_page_offset,
          column_width: context.col_width,
          content_height: context.content_height,
          position: { row: 3, col: 1 },
          show_page_num: true
        )
        draw_column(left_context)
      end

      def draw_right_column_content(context)
        right_context = build_column_context(
          lines: context.wrapped_lines,
          offset: context.right_page_offset,
          column_width: context.col_width,
          content_height: context.content_height,
          position: { row: 3, col: context.col_width + 5 },
          show_page_num: false
        )
        draw_column(right_context)
      end

      def draw_column_divider(context)
        draw_divider(context.total_height, context.col_width)
      end

      def build_column_context(lines:, offset:, column_width:, content_height:, position:,
                               show_page_num:)
        Models::PageRenderingContext.new(
          lines: lines,
          offset: offset,
          dimensions: Models::Dimensions.new(width: column_width, height: content_height),
          position: Models::Position.new(row: position[:row], col: position[:col]),
          show_page_num: show_page_num
        )
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

      def draw_single_screen_dynamic(height, width)
        return unless @page_manager

        page_data = @page_manager.get_page(@state.current_page_index)
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
        chapter = @doc.get_chapter(@state.current_chapter)
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
        context = PageSetupBuildContext.new(
          lines_in_page, wrapped, col_width, col_start, content_height, displayable_lines
        )
        build_page_setup(context)
      end

      def build_page_setup(context)
        Builders::PageSetupBuilder.new
                                  .with_lines(context.lines)
                                  .with_wrapped(context.wrapped)
                                  .with_dimensions(context.col_width,
                                                   context.content_height,
                                                   context.displayable_lines)
                                  .with_position(context.col_start)
                                  .build
      end

      def extract_lines_in_page(wrapped, displayable_lines)
        wrapped.slice(@state.single_page, displayable_lines) || []
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
          offset: @state.single_page,
          dimensions: Models::Dimensions.new(width: setup[:col_width],
                                             height: setup[:displayable_lines]),
          position: Models::Position.new(row: start_row, col: setup[:col_start]),
          show_page_num: false
        )
      end
    end
  end
end
