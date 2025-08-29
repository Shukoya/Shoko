# frozen_string_literal: true

module EbookReader
  module Services
    # TEMPORARY: Compatibility wrapper for Services::CoordinateService
    # This delegates to the domain service until all references are migrated
    class CoordinateService
      def self.mouse_to_terminal(x, y)
        container = Domain::ContainerFactory.create_default_container
        coordinate_service = container.resolve(:coordinate_service)
        coordinate_service.mouse_to_terminal(x, y)
      end

      def self.terminal_to_mouse(x, y)
        container = Domain::ContainerFactory.create_default_container
        coordinate_service = container.resolve(:coordinate_service)
        coordinate_service.terminal_to_mouse(x, y)
      end

      def self.normalize_selection_range(range)
        container = Domain::ContainerFactory.create_default_container
        coordinate_service = container.resolve(:coordinate_service)
        coordinate_service.normalize_selection_range(range)
      end

      def self.calculate_popup_position(position, width, height)
        container = Domain::ContainerFactory.create_default_container
        coordinate_service = container.resolve(:coordinate_service)
        coordinate_service.calculate_popup_position(position, width, height)
      end

      def self.within_bounds?(x, y, bounds)
        container = Domain::ContainerFactory.create_default_container
        coordinate_service = container.resolve(:coordinate_service)
        coordinate_service.within_bounds?(x, y, bounds)
      end
    end
  end
end