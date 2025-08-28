# frozen_string_literal: true

module EbookReader
  module Components
    # Standard interface contract for all UI components.
    # Defines the required methods and behavior for component lifecycle.
    module ComponentInterface
      # Called once when component is first rendered
      def mount
        raise NotImplementedError, 'Components must implement #mount'
      end

      # Called when component is removed from the UI
      def unmount
        raise NotImplementedError, 'Components must implement #unmount'
      end

      # Render this component into the given surface within bounds
      # @param surface [Surface] Terminal surface wrapper
      # @param bounds [Rect] Local bounds for this component
      def render(surface, bounds)
        raise NotImplementedError, 'Components must implement #render'
      end

      # Handle input key for this component
      # @param key [String] Input key
      # @return [Symbol] :handled or :pass_through
      def handle_input(_key)
        :pass_through
      end

      # Component height calculation for layout
      # @param available_height [Integer] Total height available from parent
      # @return [Integer, Symbol] Height requirement
      def preferred_height(_available_height)
        :flexible
      end

      # Component width calculation for layout
      # @param available_width [Integer] Total width available from parent
      # @return [Integer, Symbol] Width requirement
      def preferred_width(_available_width)
        :flexible
      end

      # Check if component needs re-rendering
      # @return [Boolean]
      def needs_update?
        true
      end

      # Mark component as updated (no longer needs re-render)
      def mark_updated
        # Default implementation - override if needed
      end

      # Validate that a class properly implements the interface
      def self.validate_implementation(klass)
        required_methods = %i[mount unmount render]
        missing = required_methods.reject { |method| klass.method_defined?(method) }

        unless missing.empty?
          raise ArgumentError, "#{klass} missing required methods: #{missing.join(', ')}"
        end

        true
      end

      # Helper method to ensure a component follows the interface
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def validate_interface!
          ComponentInterface.validate_implementation(self)
        end
      end
    end
  end
end
