# frozen_string_literal: true

module EbookReader
  module Components
    # Base interface for all UI components
    class BaseComponent
      # Render this component into the given surface within bounds
      # @param surface [Surface] terminal surface wrapper
      # @param bounds [Rect] local bounds for this component
      def render(surface, bounds)
        # to be implemented by subclasses
      end

      # Handle input key for this component
      # Return :handled or :pass_through
      def handle_input(_key)
        :pass_through
      end

      # Optional preferred height in rows; return nil for flexible
      def preferred_height(_available_height)
        nil
      end
    end
  end
end

