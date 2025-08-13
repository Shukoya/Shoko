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
        surface = Components::Surface.new(Terminal)
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
    end
  end
end