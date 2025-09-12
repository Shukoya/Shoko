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
        vm = view_model
        vm_mode = vm.mode
        vm_view = vm.view_mode
        read_mode = (vm_mode == :read)
        if vm_view == :single && read_mode
          render_single_mode_footer(surface, bounds, vm)
        elsif vm_view == :split && read_mode
          render_split_mode_footer(surface, bounds, vm)
        else
          render_default_footer(surface, bounds, vm)
        end

        render_message_overlay(surface, bounds, vm)
      end

      def render_single_mode_footer(surface, bounds, view_model)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        height = bounds.height
        return unless view_model.show_page_numbers

        pinfo = view_model.page_info
        current = pinfo[:current].to_i
        total = pinfo[:total].to_i
        return if current <= 0 && total <= 0

        page_text = page_label(current, total)
        centered_col = center_col(width, page_text.length)
        write_colored(surface, bounds, height, centered_col,
                      page_text,
                      ui::COLOR_TEXT_DIM + ui::COLOR_TEXT_SECONDARY)
      end

      def render_split_mode_footer(surface, bounds, view_model)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        height = bounds.height
        page_info = view_model.page_info
        left = page_info[:left]
        return unless view_model.show_page_numbers && left

        left_current = left[:current].to_i
        left_total = left[:total].to_i
        return if left_current <= 0 && left_total <= 0

        # Left page number
        left_text = page_label(left_current, left_total)
        left_col = quarter_center_col(width, left_text.length, :left)
        dim_secondary = EbookReader::Constants::UIConstants::COLOR_TEXT_DIM + EbookReader::Constants::UIConstants::COLOR_TEXT_SECONDARY
        write_colored(surface, bounds, height, left_col, left_text, dim_secondary)

        # Right page number
        right = page_info[:right]
        return unless right

        right_current = right[:current].to_i
        right_total = right[:total].to_i
        right_text = page_label(right_current, right_total)
        right_col = quarter_center_col(width, right_text.length, :right)
        write_colored(surface, bounds, height, right_col, right_text, dim_secondary)
      end

      def render_default_footer(surface, bounds, view_model)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        height = bounds.height
        row1 = [height - 1, 1].max

        # Progress left
        left_prog = "[#{view_model.current_chapter + 1}/#{view_model.total_chapters}]"
        write_colored(surface, bounds, row1, 1,
                      left_prog,
                      ui::COLOR_TEXT_ACCENT)

        # Mode center
        mode_label = view_model.view_mode == :split ? '[SPLIT]' : '[SINGLE]'
        page_mode = view_model.page_numbering_mode.to_s.upcase
        mode_text = "#{mode_label} [#{page_mode}]"
        write_colored(surface, bounds, row1, [(width / 2) - 10, 1].max,
                      mode_text,
                      ui::COLOR_TEXT_WARNING)

        # Status right
        right_prog = "L#{view_model.line_spacing.to_s[0]} B#{view_model.bookmarks.count}"
        write_colored(surface, bounds, row1, [width - right_prog.length - 1, 1].max,
                      right_prog,
                      ui::COLOR_TEXT_ACCENT)

        # Second line with doc metadata
        return unless height >= 2

        title_text = view_model.document_title[0, [width - 15, 0].max]
        write_colored(surface, bounds, height, 1,
                      "[#{title_text}]",
                      ui::COLOR_TEXT_PRIMARY)
        write_colored(surface, bounds, height, [width - 10, 1].max,
                      "[#{view_model.language}]",
                      ui::COLOR_TEXT_PRIMARY)
      end

      def render_message_overlay(surface, bounds, view_model)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        height = bounds.height
        msg = view_model.message
        return unless msg && !msg.to_s.empty?

        text = " #{msg} "
        col = [(width - text.length) / 2, 1].max
        mid_row = [(height / 2.0).ceil, 1].max
        write_colored(surface, bounds, mid_row, col,
                      text,
                      ui::BG_PRIMARY + ui::BG_ACCENT)
      end

      # ----- helpers -----
      def page_label(current, total)
        total.positive? ? "#{current} / #{total}" : "Page #{current}"
      end

      def center_col(width, text_len)
        [(width - text_len) / 2, 1].max
      end

      def quarter_center_col(width, text_len, side)
        half = text_len / 2
        return [(width / 4) - half, 1].max if side == :left

        [(3 * width / 4) - half, 1].max
      end

      def write_colored(surface, bounds, row, col, text, color_prefix)
        surface.write(bounds, row, col, color_prefix + text + Terminal::ANSI::RESET)
      end
    end
  end
end
