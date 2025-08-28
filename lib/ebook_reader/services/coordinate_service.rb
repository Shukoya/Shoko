# frozen_string_literal: true

module EbookReader
  module Services
    # DEPRECATED: Legacy compatibility layer - delegates to Domain::Services::CoordinateService
    # This file will be deleted in Phase 2. Use Domain::Services::CoordinateService directly.
    class CoordinateService
      # Delegate all calls to the domain service
      def self.method_missing(method, *, **)
        domain_service = Domain::ContainerFactory.create_default_container.resolve(:coordinate_service)
        domain_service.send(method, *, **)
      end

      def self.respond_to_missing?(method, include_private = false)
        domain_service = Domain::ContainerFactory.create_default_container.resolve(:coordinate_service)
        domain_service.respond_to?(method, include_private) || super
      end
    end
  end
end
