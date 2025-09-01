# frozen_string_literal: true

module EbookReader
  module UI
    # Base interface for all screen components in the main menu system.
    # Provides a consistent interface for rendering screens to surfaces.
    class BaseScreen
      # Render this screen to the provided surface within the given bounds.
      # All concrete screen implementations must override this method.
      #
      # @param surface [Components::Surface] The surface to render to
      # @param bounds [Components::Rect] The area within which to render
      # @return [void]
      def render_to_surface(surface, bounds)
        raise NotImplementedError, "#{self.class} must implement #render_to_surface"
      end

      # Optional method for screens that have their own drawing logic.
      # This provides compatibility with screens that still use Terminal directly.
      #
      # @param height [Integer] Terminal height
      # @param width [Integer] Terminal width
      # @return [void]
      def draw(height, width)
        terminal_service = resolve_terminal_service
        surface = terminal_service ? terminal_service.create_surface : Components::Surface.new(Terminal)
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        render_to_surface(surface, bounds)
      end

      protected

      # Helper method to safely access UI constants
      def ui_constants
        EbookReader::Constants::UIConstants
      end

      # Helper method to get terminal ANSI codes
      def ansi
        Terminal::ANSI
      end

      # Best-effort resolution to avoid hard-coding Terminal in UI
      def resolve_terminal_service
        # Prefer injected services/dependencies if present
        if respond_to?(:services) && services
          return services.resolve(:terminal_service) if services.respond_to?(:resolve)
        end

        if instance_variable_defined?(:@dependencies)
          deps = instance_variable_get(:@dependencies)
          return deps.resolve(:terminal_service) if deps && deps.respond_to?(:resolve)
        end

        nil
      rescue StandardError
        nil
      end
    end
  end
end
