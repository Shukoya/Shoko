# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'

module EbookReader
  module Components
    # Overlay that renders the popup menu component if present
    class PopupOverlayComponent < BaseComponent
      def initialize(controller)
        super()
        @controller = controller
        state = @controller.state
        state.add_observer(self, :selection)
        @needs_redraw = true
      end

      def preferred_height(_available_height)
        0 # Overlays don't consume layout height
      end

      def do_render(surface, bounds)
        popup = @controller.state.get([:reader, :popup_menu])
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
