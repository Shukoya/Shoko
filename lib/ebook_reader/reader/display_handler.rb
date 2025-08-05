# frozen_string_literal: true

module EbookReader
  class Reader
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

        if full_redraw_needed?(size_changed)
          Terminal.start_frame
        end

        draw_header_if_changed(height, width, current_state)
        draw_content_if_changed(height, width, current_state)
        draw_footer_if_changed(height, width, current_state)
        draw_message(height, width) if @message

        if full_redraw_needed?(size_changed)
          Terminal.end_frame
        end

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
        old_offset = @last_rendered_state[:page_offset] || -1
        new_offset = state[:page_offset]
        if (old_offset - new_offset).abs == 1
          shift_and_draw_single_line(old_offset, new_offset, height, width)
        else
          draw_reading_content(height, width)
        end
      end

      def shift_and_draw_single_line(_old_offset, _new_offset, height, width)
        # Fallback to full redraw; differential line drawing can be added later
        draw_reading_content(height, width)
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
