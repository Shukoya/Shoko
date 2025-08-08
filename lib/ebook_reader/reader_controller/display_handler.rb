# frozen_string_literal: true

module EbookReader
  class ReaderController
    # Handles screen rendering coordination
    module DisplayHandler
      def draw_screen
        height, width = Terminal.size
        current_state = capture_render_state(width, height)
        size_changed = size_changed?(width, height)
        if size_changed
          refresh_page_map(width, height)
          @render_cache.mark_all_dirty if defined?(@render_cache)
          Terminal.clear_buffer_cache if Terminal.respond_to?(:clear_buffer_cache)
        end

        Terminal.start_frame if full_redraw_needed?(size_changed)

        draw_header_if_changed(height, width, current_state)
        draw_content_if_changed(height, width, current_state)
        draw_footer_if_changed(height, width, current_state)
        draw_message(height, width) if @message

        Terminal.end_frame if full_redraw_needed?(size_changed)

        @last_rendered_state = current_state
      end

      private

      def draw_header(_height, width)
        header_context = UI::ReaderRenderer::HeaderContext.new(
          @doc, width, @config.view_mode, @mode
        )
        @renderer.render_header(header_context)
      end

      def draw_content(height, width)
        case @mode
        when :help
          draw_help_screen(height, width)
        when :toc
          draw_toc_screen(height, width)
        when :bookmarks
          draw_bookmarks_screen(height, width)
        when :annotations, :annotation_editor
          @current_mode&.draw(height, width)
        else
          draw_reading_content(height, width)
        end
      end

      def draw_header_if_changed(height, width, state)
        hash = [@doc&.title, state[:mode], width].hash
        @render_cache.get_or_render(:header, hash) do
          draw_header(height, width)
        end
      end

      def draw_footer_if_changed(height, width, state)
        # Do not draw the footer when the popup menu is active to avoid clutter
        return if state[:mode] == :popup_menu

        pages = calculate_current_pages
        hash = [pages[:current], pages[:total], width, state[:mode]].hash
        @render_cache.get_or_render(:footer, hash) do
          draw_footer(height, width)
        end
      end

      def draw_content_if_changed(height, width, state)
        content_hash = generate_content_hash(state)
        @render_cache.get_or_render(:content, content_hash) do
          if state[:mode] == :read
            draw_reading_content_differential(height, width, state)
          else
            draw_content(height, width)
          end
        end
      end

      def draw_reading_content_differential(height, width, state)
        return draw_reading_content(height, width) unless @config.page_numbering_mode == :absolute

        old_offset = @last_rendered_state[:page_offset]
        new_offset = state[:page_offset]

        # We can only do differential updates for single-line scrolls
        if old_offset && (new_offset - old_offset).abs == 1
          shift_and_draw_single_line(old_offset, new_offset, height, width)
        else
          draw_reading_content(height, width)
        end
      end

      def shift_and_draw_single_line(old_offset, new_offset, height, width)
        direction = new_offset > old_offset ? :down : :up

        # Define the scrollable content area (excluding header and footer)
        content_top = 2
        content_height = height - 2

        Terminal.scroll_area(content_top, content_height, direction)

        # Now, draw the new line that has scrolled into view
        if @config.view_mode == :split
          draw_new_line_in_split_view(direction, content_height, width)
        else
          draw_new_line_in_single_view(direction, content_height, width)
        end
      end

      def draw_new_line_in_split_view(direction, content_height, width)
        col_width, actual_height = get_layout_metrics(width, content_height)
        chapter_lines = get_wrapped_chapter_lines(col_width)

        left_offset, right_offset = if direction == :down
                                      [@left_page + actual_height - 1,
                                       @right_page + actual_height - 1]
                                    else
                                      [
                                        @left_page, @right_page
                                      ]
                                    end

        # Draw left page line
        left_line = chapter_lines[left_offset]
        draw_line_at(left_line, direction == :down ? content_height : 1, 1, col_width) if left_line

        # Draw right page line
        right_line = chapter_lines[right_offset]
        return unless right_line

        draw_line_at(right_line, direction == :down ? content_height : 1, col_width + 3,
                     col_width)
      end

      def draw_new_line_in_single_view(direction, content_height, width)
        col_width, actual_height = get_layout_metrics(width, content_height)
        chapter_lines = get_wrapped_chapter_lines(col_width)

        line_offset = direction == :down ? @single_page + actual_height - 1 : @single_page
        line_to_draw = chapter_lines[line_offset]

        start_col = (width - col_width) / 2
        return unless line_to_draw

        draw_line_at(line_to_draw, direction == :down ? content_height : 1, start_col,
                     col_width)
      end

      def get_wrapped_chapter_lines(col_width)
        # Simple caching mechanism for wrapped lines per chapter
        @wrapped_lines_cache ||= {}
        @wrapped_lines_cache[@current_chapter] ||= wrap_lines(
          @doc.get_chapter(@current_chapter).lines, col_width
        )
      end

      def draw_line_at(text, row, col, width)
        # This is a simplified drawing method. In a real scenario, you'd
        # use the existing `draw_line` or a similar helper.
        Terminal.write(row, col, text.to_s.ljust(width)[0, width])

        # Also update the @rendered_lines cache for the new line
        (@rendered_lines ||= {})[row] = { col: col, text: text.to_s }
      end

      def capture_render_state(width, height)
        {
          width: width,
          height: height,
          page_offset: @config.view_mode == :split ? @left_page : @single_page,
          chapter: @current_chapter,
          mode: @mode,
        }
      end

      def generate_content_hash(state)
        [state[:chapter], state[:page_offset], state[:mode]].hash
      end

      def full_redraw_needed?(size_changed)
        size_changed || @last_rendered_state.empty?
      end

      def draw_footer(height, width)
        pages = calculate_current_pages
        context = build_footer_context(height, width, pages)
        @renderer.render_footer(context)
      end

      def draw_message(height, width)
        msg_len = @message.length
        Terminal.write(
          height / 2,
          (width - msg_len) / 2,
          "#{Terminal::ANSI::BG_DARK}#{Terminal::ANSI::BRIGHT_YELLOW} #{@message} " \
          "#{Terminal::ANSI::RESET}"
        )
      end

      def build_footer_context(height, width, pages)
        context_params = footer_context_params(height, width, pages)
        Models::FooterRenderingContext.new(context_params)
      end

      def footer_context_params(height, width, pages)
        {
          height: height, width: width, doc: @doc,
          chapter: @current_chapter, pages: pages,
          view_mode: @config.view_mode, mode: @mode,
          line_spacing: @config.line_spacing, bookmarks: @bookmarks
        }
      end
    end
  end
end
