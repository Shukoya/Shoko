# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    class FooterComponent < BaseComponent
      def initialize(view_model_provider = nil)
        super()
        @view_model_provider = view_model_provider
        @cached_view_model = nil
      end

      def preferred_height(_available_height)
        vm = resolve_view_model
        return 0 unless vm

        height = 0
        height = 1 if renderable_page_info?(vm)
        height += 1 if message_present?(vm)
        height
      end

      def do_render(surface, bounds)
        vm = resolve_view_model
        return unless vm

        page_rows = renderable_page_info?(vm) ? 1 : 0
        if page_rows.positive?
          page_row = [bounds.height - (message_present?(vm) ? 1 : 0), 1].max
          render_page_info(surface, bounds, vm, page_row)
        end

        render_message_overlay(surface, bounds, vm) if message_present?(vm)
      ensure
        @cached_view_model = nil
      end

      private

      def resolve_view_model
        return nil unless @view_model_provider

        @cached_view_model ||= @view_model_provider.call
      rescue StandardError
        nil
      end

      def message_present?(view_model)
        msg = view_model&.message
        msg && !msg.to_s.empty?
      end

      def renderable_page_info?(view_model)
        disallowed_modes = %i[help toc bookmarks]
        return false if view_model.respond_to?(:mode) && disallowed_modes.include?(view_model.mode)
        return false unless view_model.respond_to?(:show_page_numbers) && view_model.show_page_numbers

        info = view_model.page_info
        info && !info.empty?
      end

      def render_page_info(surface, bounds, view_model, row)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        info = view_model.page_info

        if view_model.view_mode == :split && info[:left]
          render_split_page_info(surface, bounds, info, width, row, ui)
        else
          render_single_page_info(surface, bounds, info, width, row, ui)
        end
      end

      def render_single_page_info(surface, bounds, info, width, row, ui)
        current = info[:current].to_i
        total = info[:total].to_i
        return if current.zero? && total.zero?

        label = page_label(current, total)
        col = center_col(width, label.length)
        write_colored(surface, bounds, row, col, label, ui::COLOR_TEXT_DIM + ui::COLOR_TEXT_SECONDARY)
      end

      def render_split_page_info(surface, bounds, info, width, row, ui)
        left = info[:left]
        right = info[:right]
        return unless left

        dim_secondary = ui::COLOR_TEXT_DIM + ui::COLOR_TEXT_SECONDARY

        left_label = page_label(left[:current].to_i, left[:total].to_i)
        left_col = quarter_center_col(width, left_label.length, :left)
        write_colored(surface, bounds, row, left_col, left_label, dim_secondary) unless left_label.empty?

        return unless right

        right_label = page_label(right[:current].to_i, right[:total].to_i)
        right_col = quarter_center_col(width, right_label.length, :right)
        write_colored(surface, bounds, row, right_col, right_label, dim_secondary) unless right_label.empty?
      end

      def render_message_overlay(surface, bounds, view_model)
        ui = EbookReader::Constants::UIConstants
        width = bounds.width
        message = " #{view_model.message} "
        col = [(width - message.length) / 2, 1].max
        row = bounds.height
        surface.write(bounds, row, col,
                      "#{ui::BG_PRIMARY}#{ui::BG_ACCENT}#{message}#{Terminal::ANSI::RESET}")
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
