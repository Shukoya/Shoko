# frozen_string_literal: true

module EbookReader
  class Reader
    # Handles screen rendering coordination
    module DisplayHandler
      def draw_screen
        Terminal.start_frame
        height, width = Terminal.size

        refresh_page_map(width, height)
        draw_header(height, width)
        draw_content(height, width)
        draw_footer(height, width)
        draw_message(height, width) if @message

        Terminal.end_frame
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
        when :help then draw_help_screen(height, width)
        when :toc then draw_toc_screen(height, width)
        when :bookmarks then draw_bookmarks_screen(height, width)
        else draw_reading_content(height, width)
        end
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
        Models::FooterRenderingContext.new(
          height: height,
          width: width,
          doc: @doc,
          chapter: @current_chapter,
          pages: pages,
          view_mode: @config.view_mode,
          mode: @mode,
          line_spacing: @config.line_spacing,
          bookmarks: @bookmarks
        )
      end
    end
  end
end
