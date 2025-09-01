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
      # Prefer using render(surface, bounds) via TerminalService
      def draw(height, width)
        terminal_service = resolve_terminal_service
        surface = terminal_service ? terminal_service.create_surface : Components::Surface.new(Terminal)
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

      # Try to resolve TerminalService through injected dependencies
      def resolve_terminal_service
        # UIController has @dependencies; ReaderController also injects
        deps = nil
        if reader && reader.instance_variable_defined?(:@dependencies)
          deps = reader.instance_variable_get(:@dependencies)
        elsif respond_to?(:services) && services
          deps = services
        end
        return nil unless deps && deps.respond_to?(:resolve)
        deps.resolve(:terminal_service)
      rescue StandardError
        nil
      end
    end
  end
end
