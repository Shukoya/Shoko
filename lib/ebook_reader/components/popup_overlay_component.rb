# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    # Overlay that renders the popup menu component if present
    class PopupOverlayComponent < BaseComponent
      def initialize(controller)
        @controller = controller
        state = @controller.instance_variable_get(:@state)
        state.add_observer(self, :selection)
        @needs_redraw = true
      end

      def preferred_height(_available_height)
        # Overlays don't consume layout height
        0
      end

      def render(surface, bounds)
        popup = @controller.instance_variable_get(:@state).popup_menu
        return unless popup.respond_to?(:render_with_surface)

        popup.render_with_surface(surface, bounds)
        @needs_redraw = false
      end

      def state_changed(_field, _old, _new)
        @needs_redraw = true
      end
    end
  end
end
