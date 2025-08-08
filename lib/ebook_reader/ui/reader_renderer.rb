# frozen_string_literal: true

module EbookReader
  module UI
    # Handles rendering for Reader
    class ReaderRenderer
      include Terminal::ANSI

      def initialize(config)
        @config = config
      end

      HeaderContext = Struct.new(:doc, :width, :view_mode, :mode)

      def render_header(context)
        if single_view_reading_mode?(context.view_mode, context.mode)
          render_centered_title(context.doc, context.width)
        else
          render_standard_header(context.width)
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

      # ===== Help / ToC Screens =====

      def render_help_lines(height, width, lines)
        start_row = [(height - lines.size) / 2, 1].max
        lines.each_with_index do |line, idx|
          row = start_row + idx
          break if row >= height - 2
          col = [(width - line.length) / 2, 1].max
          Terminal.write(row, col, WHITE + line + RESET)
        end
      end

      def render_toc_screen(height, width, doc, selected_index)
        Terminal.write(1, 2, "#{BRIGHT_CYAN}📖 Table of Contents#{RESET}")
        Terminal.write(1, [width - 30, 40].max, "#{DIM}[t/ESC] Back to Reading#{RESET}")

        list_start = 4
        list_height = height - 6
        chapters = doc.chapters
        return if chapters.empty?

        visible_start = [selected_index - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, chapters.length].min
        (visible_start...visible_end).each_with_index do |idx, row|
          chapter = chapters[idx]
          line = (chapter.title || 'Untitled')[0, width - 6]
          y = list_start + row
          if idx == selected_index
            Terminal.write(y, 2, BRIGHT_GREEN + '▸ ' + RESET)
            Terminal.write(y, 4, BRIGHT_WHITE + line + RESET)
          else
            Terminal.write(y, 4, WHITE + line + RESET)
          end
        end

        Terminal.write(height - 1, 2, DIM + "↑↓ Navigate • Enter Jump • t/ESC Back" + RESET)
      end

      # ===== Bookmarks Screen Rendering =====
      BookmarksContext = Struct.new(
        :height, :width, :doc, :bookmarks, :selected,
        keyword_init: true
      )

      def render_bookmarks_screen(context)
        render_bookmarks_header(context.width)
        if context.bookmarks.empty?
          render_empty_bookmarks(context.height, context.width)
        else
          render_bookmarks_list(context)
        end
        render_bookmarks_footer(context.height)
      end

      def render_bookmarks_header(width)
        Terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}🔖 Bookmarks#{Terminal::ANSI::RESET}")
        Terminal.write(1, [width - 40, 40].max,
                       "#{Terminal::ANSI::DIM}[B/ESC] Back [d] Delete#{Terminal::ANSI::RESET}")
      end

      def render_empty_bookmarks(height, width)
        Terminal.write(height / 2, (width - 30) / 2,
                       "#{Terminal::ANSI::DIM}No bookmarks yet. Press 'b' while reading to add one.#{Terminal::ANSI::RESET}")
      end

      def render_bookmarks_list(context)
        list_start = 4
        list_height = (context.height - 6) / 2
        visible_start = [context.selected - (list_height / 2), 0].max
        visible_end = [visible_start + list_height, context.bookmarks.length].min
        (visible_start...visible_end).each_with_index do |idx, row_idx|
          bookmark = context.bookmarks[idx]
          chapter = context.doc.get_chapter(bookmark.chapter_index)
          chapter_title = chapter&.title || "Chapter #{bookmark.chapter_index + 1}"

          row = list_start + (row_idx * 2)
          selected = (idx == context.selected)
          draw_bookmark_item(row, context.width, bookmark, chapter_title, selected)
        end
      end

      def draw_bookmark_item(row, width, bookmark, chapter_title, selected)
        chapter_text = "Ch. #{bookmark.chapter_index + 1}: #{chapter_title[0, width - 20]}"
        text_snippet = bookmark.text_snippet[0, width - 8]

        if selected
          Terminal.write(row, 2, "#{Terminal::ANSI::BRIGHT_GREEN}▸ #{Terminal::ANSI::RESET}")
          Terminal.write(row, 4, "#{Terminal::ANSI::BRIGHT_WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")
          Terminal.write(row + 1, 6, "#{Terminal::ANSI::ITALIC}#{Terminal::ANSI::GRAY}#{text_snippet}#{Terminal::ANSI::RESET}")
        else
          Terminal.write(row, 4, "#{Terminal::ANSI::WHITE}#{chapter_text}#{Terminal::ANSI::RESET}")
          Terminal.write(row + 1, 6, "#{Terminal::ANSI::DIM}#{Terminal::ANSI::GRAY}#{text_snippet}#{Terminal::ANSI::RESET}")
        end
      end

      def render_bookmarks_footer(height)
        Terminal.write(height - 1, 2,
                       "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Jump • d Delete • B/ESC Back#{Terminal::ANSI::RESET}")
      end
    end
  end
end
