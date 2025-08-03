# frozen_string_literal: true

module EbookReader
  module UI
    # Handles rendering for Reader
    class ReaderRenderer
      include Terminal::ANSI

      def initialize(config)
        @config = config
      end

      def render_header(doc, width, view_mode, mode)
        if single_view_reading_mode?(view_mode, mode)
          render_centered_title(doc, width)
        else
          render_standard_header(width)
        end
      end

      SplitViewContext = Struct.new(
        :height, :width, :doc, :chapter, :view_mode, :line_spacing, :bookmarks,
        keyword_init: true
      )

      StatusContext = Struct.new(:row, :width, :line_spacing, :bookmarks,
                                 keyword_init: true)

      def render_footer(context)
        if context.view_mode == :single && context.mode == :read
          render_single_view_footer(context.height, context.width, context.pages)
        else
          render_split_view_footer(split_context_from(context))
        end
      end

      def split_context_from(context)
        SplitViewContext.new(height: context.height, width: context.width, doc: context.doc,
                             chapter: context.chapter, view_mode: context.view_mode,
                             line_spacing: context.line_spacing, bookmarks: context.bookmarks)
      end

      private

      def single_view_reading_mode?(view_mode, mode)
        view_mode == :single && mode == :read
      end

      def render_centered_title(doc, width)
        title_text = doc.title
        centered_col = [(width - title_text.length) / 2, 1].max
        Terminal.write(1, centered_col, WHITE + title_text + RESET)
      end

      def render_standard_header(width)
        Terminal.write(1, 1, "#{WHITE}Reader#{RESET}")
        right_text = 'q:Quit ?:Help t:ToC B:Bookmarks'
        Terminal.write(1, [width - right_text.length + 1, 1].max,
                       WHITE + right_text + RESET)
      end

      def render_single_view_footer(height, width, pages)
        return unless @config.show_page_numbers && pages[:total].positive?

        page_text = "#{pages[:current]} / #{pages[:total]}"
        centered_col = [(width - page_text.length) / 2, 1].max
        Terminal.write(height, centered_col, DIM + GRAY + page_text + RESET)
      end

      def render_split_view_footer(context)
        footer_row1 = [context.height - 1, 3].max

        render_footer_progress(footer_row1, context.doc, context.chapter)
        render_footer_mode(footer_row1, context.width, context.view_mode)
        render_footer_status(StatusContext.new(row: footer_row1, width: context.width,
                                               line_spacing: context.line_spacing,
                                               bookmarks: context.bookmarks))

        render_second_footer_line(context.height, context.width, context.doc) if context.height > 3
      end

      def render_footer_progress(row, doc, chapter)
        left_prog = "[#{chapter + 1}/#{doc.chapter_count}]"
        Terminal.write(row, 1, BLUE + left_prog + RESET)
      end

      def render_footer_mode(row, width, view_mode)
        mode_label = view_mode == :split ? '[SPLIT]' : '[SINGLE]'
        page_mode = @config.page_numbering_mode.to_s.upcase
        mode_text = "#{mode_label} [#{page_mode}]"
        Terminal.write(row, [(width / 2) - 10, 20].max, YELLOW + mode_text + RESET)
      end

      def render_footer_status(context)
        right_prog = "L#{context.line_spacing.to_s[0]} B#{context.bookmarks.count}"
        Terminal.write(context.row, [context.width - right_prog.length - 1, 40].max,
                       BLUE + right_prog + RESET)
      end

      def render_second_footer_line(height, width, doc)
        Terminal.write(height, 1, WHITE + "[#{doc.title[0, width - 15]}]" + RESET)
        Terminal.write(height, [width - 10, 50].max,
                       WHITE + "[#{doc.language}]" + RESET)
      end
    end
  end
end
