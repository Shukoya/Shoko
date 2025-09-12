# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../constants/ui_constants'

module EbookReader
  module Components
    class HeaderComponent < BaseComponent
      include Constants::UIConstants

      def initialize(view_model_provider = nil, theme = :dark)
        super()
        @view_model_provider = view_model_provider
        @theme = theme
      end

      def preferred_height(_available_height)
        1 # Fixed height header
      end

      def do_render(surface, bounds)
        return unless @view_model_provider

        view_model = @view_model_provider.call
        render_header(surface, bounds, view_model)
      end

      private

      def render_header(surface, bounds, view_model)
        width = bounds.width

        if view_model.view_mode == :single && view_model.mode == :read
          render_single_view_header(surface, bounds, view_model, width)
        else
          render_default_header(surface, bounds, width)
        end
      end

      def render_single_view_header(surface, bounds, view_model, width)
        reset = Terminal::ANSI::RESET
        title_text = view_model.document_title.to_s
        centered_col = [(width - title_text.length) / 2, 1].max
        surface.write(bounds, 1, centered_col, "#{COLOR_TEXT_PRIMARY}#{title_text}#{reset}")
      end

      def render_default_header(surface, bounds, width)
        reset = Terminal::ANSI::RESET
        surface.write(bounds, 1, 1, "#{COLOR_TEXT_PRIMARY}Reader#{reset}")
        right_text = 'q:Quit ?:Help t:ToC B:Bookmarks'
        right_col = [width - right_text.length + 1, 1].max
        surface.write(bounds, 1, right_col, "#{COLOR_TEXT_PRIMARY}#{right_text}#{reset}")
      end
    end
  end
end
