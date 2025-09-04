# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    class FooterComponent < BaseComponent
      def initialize(view_model_provider = nil)
        super()
        @view_model_provider = view_model_provider
      end

      def preferred_height(_available_height)
        2 # Fixed height footer
      end

      def do_render(surface, bounds)
        return unless @view_model_provider

        view_model = @view_model_provider.call
        render_footer(surface, bounds, view_model)
      end

      private

      def render_footer(surface, bounds, view_model)
        width = bounds.width
        height = bounds.height

        if view_model.view_mode == :single && view_model.mode == :read
          render_single_mode_footer(surface, bounds, view_model, width, height)
        elsif view_model.view_mode == :split && view_model.mode == :read
          render_split_mode_footer(surface, bounds, view_model, width, height)
        else
          render_default_footer(surface, bounds, view_model, width, height)
        end

        render_message_overlay(surface, bounds, view_model, width, height)
      end

      def render_single_mode_footer(surface, bounds, view_model, width, height)
        return unless view_model.show_page_numbers

        current = view_model.page_info[:current].to_i
        total = view_model.page_info[:total].to_i
        return if current <= 0 && total <= 0

        page_text = if total.positive?
                      "#{current} / #{total}"
                    else
                      "Page #{current}"
                    end
        centered_col = [(width - page_text.length) / 2, 1].max
        surface.write(bounds, height, centered_col,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_DIM + EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY + page_text + Terminal::ANSI::RESET)
      end

      def render_split_mode_footer(surface, bounds, view_model, width, height)
        page_info = view_model.page_info
        return unless view_model.show_page_numbers && page_info[:left]

        left_current = page_info[:left][:current].to_i
        left_total = page_info[:left][:total].to_i
        return if left_current <= 0 && left_total <= 0

        # Left page number
        left_text = if left_total.positive?
                      "#{left_current} / #{left_total}"
                    else
                      "Page #{left_current}"
                    end
        left_col = [(width / 4) - (left_text.length / 2), 1].max
        surface.write(bounds, height, left_col,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_DIM + EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY + left_text + Terminal::ANSI::RESET)

        # Right page number
        return unless page_info[:right]

        right_current = page_info[:right][:current].to_i
        right_total = page_info[:right][:total].to_i
        right_text = if right_total.positive?
                       "#{right_current} / #{right_total}"
                     else
                       "Page #{right_current}"
                     end
        right_col = [(3 * width / 4) - (right_text.length / 2), 1].max
        surface.write(bounds, height, right_col,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_DIM + EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY + right_text + Terminal::ANSI::RESET)
      end

      def render_default_footer(surface, bounds, view_model, width, height)
        row1 = [height - 1, 1].max

        # Progress left
        left_prog = "[#{view_model.current_chapter + 1}/#{view_model.total_chapters}]"
        surface.write(bounds, row1, 1,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + left_prog + Terminal::ANSI::RESET)

        # Mode center
        mode_label = view_model.view_mode == :split ? '[SPLIT]' : '[SINGLE]'
        page_mode = view_model.page_numbering_mode.to_s.upcase
        mode_text = "#{mode_label} [#{page_mode}]"
        surface.write(bounds, row1, [(width / 2) - 10, 1].max,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_WARNING + mode_text + Terminal::ANSI::RESET)

        # Status right
        right_prog = "L#{view_model.line_spacing.to_s[0]} B#{view_model.bookmarks.count}"
        surface.write(bounds, row1, [width - right_prog.length - 1, 1].max,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + right_prog + Terminal::ANSI::RESET)

        # Second line with doc metadata
        return unless height >= 2

        title_text = view_model.document_title[0, [width - 15, 0].max]
        surface.write(bounds, height, 1,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + "[#{title_text}]" + Terminal::ANSI::RESET)
        surface.write(bounds, height, [width - 10, 1].max,
                      EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + "[#{view_model.language}]" + Terminal::ANSI::RESET)
      end

      def render_message_overlay(surface, bounds, view_model, width, height)
        return unless view_model.message && !view_model.message.to_s.empty?

        text = " #{view_model.message} "
        col = [(width - text.length) / 2, 1].max
        mid_row = [(height / 2.0).ceil, 1].max
        surface.write(bounds, mid_row, col,
                      EbookReader::Constants::UIConstants::BG_PRIMARY + EbookReader::Constants::UIConstants::BG_ACCENT + text + Terminal::ANSI::RESET)
      end
    end
  end
end
