# frozen_string_literal: true

module EbookReader
  module Application
    # RenderPipeline encapsulates the high-level rendering steps for
    # component-driven frames and full-screen mode components.
    class RenderPipeline
      def initialize(dependencies)
        @dependencies = dependencies
        @state = @dependencies.resolve(:global_state)
      end

      # Render the standard layout + overlay path
      def render_layout(surface, bounds, layout, overlay)
        # Clear rendered lines for the new frame so overlays can rely on state
        @state.dispatch(EbookReader::Domain::Actions::ClearRenderedLinesAction.new)
        layout.render(surface, bounds)
        overlay.render(surface, bounds)
      end

      # Render a dedicated full-screen component (e.g., editor)
      def render_mode_component(component, surface, bounds)
        surface.fill(bounds, ' ')
        component.render(surface, bounds)
      end

      # Generic component render helper for non-reader screens (menu, dialogs)
      def render_component(surface, bounds, component)
        surface.fill(bounds, ' ')
        component.render(surface, bounds)
      end
    end
  end
end
