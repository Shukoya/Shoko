# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      # Base class for all domain services with dependency injection support.
      # Provides standardized initialization and dependency management.
      class BaseService
        attr_reader :dependencies

        def initialize(dependencies)
          @dependencies = dependencies
          validate_dependencies
          setup_service_dependencies
        end

        protected

        # Override in subclasses to specify required dependencies
        def required_dependencies
          []
        end

        # Override in subclasses to setup specific service dependencies
        def setup_service_dependencies
          # Default implementation does nothing
        end

        # Resolve a dependency from the container
        def resolve(dependency_name)
          @dependencies.resolve(dependency_name)
        end

        # Check if a dependency is registered
        def registered?(dependency_name)
          @dependencies.registered?(dependency_name)
        end

        private

        def validate_dependencies
          return unless respond_to?(:required_dependencies)

          missing = required_dependencies.reject { |dep| registered?(dep) }
          return if missing.empty?

          raise ArgumentError, "Missing required dependencies: #{missing.join(', ')}"
        end
      end
    end
  end
end
