# frozen_string_literal: true

module EbookReader
  module Components
    # Base interface for all UI components
    class BaseComponent
      attr_reader :services

      def initialize(services = nil)
        @services = services || Services::ServiceRegistry
      end

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

      # Component height calculation contract
      # @param available_height [Integer] Total height available from parent
      # @return [Integer, :flexible, :fill] Height requirement:
      #   - Integer: Fixed height in rows
      #   - :flexible: Use as much space as needed, up to available
      #   - :fill: Take all remaining space after fixed components
      def preferred_height(_available_height)
        :flexible
      end
    end
  end
end
