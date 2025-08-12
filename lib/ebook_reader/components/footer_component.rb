# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    class FooterComponent < BaseComponent
      def initialize(controller)
        @controller = controller
        state = @controller.state
        state.add_observer(self, :mode, :current_chapter, :left_page, :right_page, :single_page)
        @needs_redraw = true
      end

      def preferred_height(_available_height)
        2 # Fixed height footer
      end

      def render(surface, bounds)
        config = @controller.config
        state = @controller.state
        doc = @controller.doc
        width = bounds.width
        height = bounds.height

        if config.view_mode == :single && state.mode == :read
          # Single mode: centered page indicator on last line
          pages = @controller.calculate_current_pages
          if @controller.config.show_page_numbers && pages[:total].positive?
            page_text = "#{pages[:current]} / #{pages[:total]}"
            centered_col = [(width - page_text.length) / 2, 1].max
            surface.write(bounds, height, centered_col,
                          Terminal::ANSI::DIM + Terminal::ANSI::GRAY + page_text + Terminal::ANSI::RESET)
          end
        elsif config.view_mode == :split && state.mode == :read
          # Duo mode: show consecutive page numbers on both sides
          split_pages = @controller.calculate_split_pages
          if @controller.config.show_page_numbers && split_pages[:left][:total].positive?
            # Left page number
            left_text = "#{split_pages[:left][:current]} / #{split_pages[:left][:total]}"
            left_col = [(width / 4) - (left_text.length / 2), 1].max
            surface.write(bounds, height, left_col,
                          Terminal::ANSI::DIM + Terminal::ANSI::GRAY + left_text + Terminal::ANSI::RESET)
            
            # Right page number
            right_text = "#{split_pages[:right][:current]} / #{split_pages[:right][:total]}"
            right_col = [(3 * width / 4) - (right_text.length / 2), 1].max
            surface.write(bounds, height, right_col,
                          Terminal::ANSI::DIM + Terminal::ANSI::GRAY + right_text + Terminal::ANSI::RESET)
          end
        else
          # Split/other modes — show two-line footer
          row1 = [height - 1, 1].max

          # Progress left
          left_prog = "[#{state.current_chapter + 1}/#{doc&.chapter_count}]"
          surface.write(bounds, row1, 1, Terminal::ANSI::BLUE + left_prog + Terminal::ANSI::RESET)

          # Mode center
          mode_label = config.view_mode == :split ? '[SPLIT]' : '[SINGLE]'
          page_mode = config.page_numbering_mode.to_s.upcase
          mode_text = "#{mode_label} [#{page_mode}]"
          surface.write(bounds, row1, [(width / 2) - 10, 1].max,
                        Terminal::ANSI::YELLOW + mode_text + Terminal::ANSI::RESET)

          # Status right
          bookmarks = @controller.state.bookmarks || []
          right_prog = "L#{config.line_spacing.to_s[0]} B#{bookmarks.count}"
          surface.write(bounds, row1, [width - right_prog.length - 1, 1].max,
                        Terminal::ANSI::BLUE + right_prog + Terminal::ANSI::RESET)

          # Second line with doc metadata
          if height >= 2
            title_text = (doc&.title || '')[0, [width - 15, 0].max]
            surface.write(bounds, height, 1, Terminal::ANSI::WHITE + "[#{title_text}]" + Terminal::ANSI::RESET)
            lang_text = (doc&.language || '').to_s
            surface.write(bounds, height, [width - 10, 1].max,
                          Terminal::ANSI::WHITE + "[#{lang_text}]" + Terminal::ANSI::RESET)
          end
        end

        # Optional centered message overlay in footer area (kept simple)
        message = state.message
        if message && !message.to_s.empty?
          text = " #{message} "
          col = [(width - text.length) / 2, 1].max
          mid_row = [(height / 2.0).ceil, 1].max
          surface.write(bounds, mid_row, col,
                        Terminal::ANSI::BG_DARK + Terminal::ANSI::BRIGHT_YELLOW + text + Terminal::ANSI::RESET)
        end
        @needs_redraw = false
      end

      def state_changed(_field, _old, _new)
        @needs_redraw = true
      end
    end
  end
end
