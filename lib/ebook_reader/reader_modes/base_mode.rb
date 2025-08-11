# frozen_string_literal: true

require_relative '../components/base_component'
require_relative '../components/surface'
require_relative '../components/rect'

module EbookReader
  module ReaderModes
    # Base class for all reader modes - now inherits from BaseComponent for consistency
    class BaseMode < Components::BaseComponent
      attr_reader :reader

      def initialize(reader)
        @reader = reader
      end

      # Legacy draw method for backward compatibility
      # @deprecated Use render(surface, bounds) instead
      def draw(height, width)
        surface = Components::Surface.new(Terminal)
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        render(surface, bounds)
      end

      # Component-based rendering (override in subclasses)
      def render(surface, bounds)
        raise NotImplementedError
      end

      # @abstract Override in subclasses
      def handle_input(key)
        raise NotImplementedError
      end

      protected

      def terminal
        Terminal
      end

      def config
        reader.config
      end
    end
  end
end
