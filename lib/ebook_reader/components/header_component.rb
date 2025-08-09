# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    class HeaderComponent < BaseComponent
      def initialize(controller)
        @controller = controller
        state = @controller.instance_variable_get(:@state)
        state.add_observer(self, :mode)
        @needs_redraw = true
      end

      def preferred_height(_available_height)
        1
      end

      def render(surface, bounds)
        width = bounds.width
        doc = @controller.instance_variable_get(:@doc)
        config = @controller.config
        state = @controller.instance_variable_get(:@state)

        if config.view_mode == :single && state.mode == :read
          title_text = doc&.title.to_s
          centered_col = [(width - title_text.length) / 2, 1].max
          surface.write(bounds, 1, centered_col, Terminal::ANSI::WHITE + title_text + Terminal::ANSI::RESET)
        else
          surface.write(bounds, 1, 1, "#{Terminal::ANSI::WHITE}Reader#{Terminal::ANSI::RESET}")
          right_text = 'q:Quit ?:Help t:ToC B:Bookmarks'
          right_col = [width - right_text.length + 1, 1].max
          surface.write(bounds, 1, right_col, Terminal::ANSI::WHITE + right_text + Terminal::ANSI::RESET)
        end
        @needs_redraw = false
      end

      def state_changed(_field, _old, _new)
        @needs_redraw = true
      end
    end
  end
end
