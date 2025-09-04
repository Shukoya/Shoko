# frozen_string_literal: true

module EbookReader
  module Domain
    # Dependency injection container for managing service dependencies.
    # Replaces the broken ServiceRegistry with proper lifecycle management.
    class DependencyContainer
      class DependencyError < StandardError; end
      class CircularDependencyError < DependencyError; end

      def initialize
        @services = {}
        @factories = {}
        @singletons = {}
        @resolving = Set.new
      end

      # Register a singleton service
      #
      # @param name [Symbol] Service name
      # @param service [Object] Service instance
      def register(name, service)
        @services[name] = service
      end

      # Register a factory for lazy instantiation
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc that creates the service
      def register_factory(name, &factory)
        @factories[name] = factory
      end

      # Register a singleton factory
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc
      def register_singleton(name, &factory)
        @singletons[name] = factory
      end

      # Resolve a service by name
      #
      # @param name [Symbol] Service name
      # @return [Object] Service instance
      def resolve(name)
        return @services[name] if @services.key?(name)

        detect_circular_dependency(name) do
          resolve_from_factories(name)
        end
      end

      # Resolve multiple services
      #
      # @param names [Array<Symbol>] Service names
      # @return [Hash<Symbol, Object>] Hash of name => service
      def resolve_many(*names)
        names.to_h { |name| [name, resolve(name)] }
      end

      # Check if service is registered
      #
      # @param name [Symbol] Service name
      # @return [Boolean]
      def registered?(name)
        @services.key?(name) || @factories.key?(name) || @singletons.key?(name)
      end

      # List all registered service names
      #
      # @return [Array<Symbol>]
      def service_names
        (@services.keys + @factories.keys + @singletons.keys).uniq
      end

      # Create child container with inherited services
      #
      # @return [DependencyContainer]
      def create_child
        child = self.class.new
        child.instance_variable_set(:@services, @services.dup)
        child.instance_variable_set(:@factories, @factories.dup)
        child.instance_variable_set(:@singletons, @singletons.dup)
        child
      end

      # Clear all registrations (for testing)
      def clear!
        @services.clear
        @factories.clear
        @singletons.clear
      end

      private

      def resolve_from_factories(name)
        if @singletons.key?(name)
          @services[name] ||= @singletons[name].call(self)
        elsif @factories.key?(name)
          @factories[name].call(self)
        else
          raise DependencyError, "Service '#{name}' not registered"
        end
      end

      def detect_circular_dependency(name)
        if @resolving.include?(name)
          raise CircularDependencyError,
                "Circular dependency detected for '#{name}'"
        end

        @resolving.add(name)
        begin
          yield
        ensure
          @resolving.delete(name)
        end
      end
    end

    # Factory methods for common service configurations
    module ContainerFactory
      def self.create_default_container
        container = DependencyContainer.new

        # Infrastructure services
        container.register_singleton(:event_bus) { Infrastructure::EventBus.new }
        container.register_singleton(:logger) { Infrastructure::Logger }
        
        # Domain event bus
        container.register_singleton(:domain_event_bus) do |c|
          Domain::Events::DomainEventBus.new(c.resolve(:event_bus))
        end

        # Domain repositories
        container.register_factory(:bookmark_repository) { |c| Domain::Repositories::BookmarkRepository.new(c) }
        container.register_factory(:annotation_repository) { |c| Domain::Repositories::AnnotationRepository.new(c) }
        container.register_factory(:progress_repository) { |c| Domain::Repositories::ProgressRepository.new(c) }
        container.register_factory(:config_repository) { |c| Domain::Repositories::ConfigRepository.new(c) }

        # Domain services with dependency injection
        container.register_factory(:navigation_service) { |c| Domain::Services::NavigationService.new(c) }
        container.register_factory(:bookmark_service) { |c| Domain::Services::BookmarkService.new(c) }
        container.register_singleton(:page_calculator) { |c| Domain::Services::PageCalculatorService.new(c) }
        container.register_factory(:coordinate_service) { |c| Domain::Services::CoordinateService.new(c) }
        container.register_factory(:selection_service) { |c| Domain::Services::SelectionService.new(c) }
        container.register_factory(:layout_service) { |c| Domain::Services::LayoutService.new(c) }
        container.register_factory(:clipboard_service) { |c| Domain::Services::ClipboardService.new(c) }
        container.register_factory(:terminal_service) { |c| Domain::Services::TerminalService.new(c) }
        container.register_factory(:annotation_service) { |c| Domain::Services::AnnotationService.new(c) }
        container.register_factory(:wrapping_service) { |c| Domain::Services::WrappingService.new(c) }

        # Infrastructure services
        container.register_factory(:document_service) do |_c|
          # DocumentService will be created per book - requires epub_path parameter
          nil # Placeholder - will be created with path parameter when needed
        end

        # Focused controllers replacing god class

        # Legacy services (to be migrated to domain)
        # TODO: Convert to domain service
        container.register_factory(:chapter_cache) do |_c|
          EbookReader::Services::ChapterCache.new
        end

        # Unified state management
        container.register_singleton(:global_state) { |c| Infrastructure::ObserverStateStore.new(c.resolve(:event_bus)) }

        # IMPORTANT: state_store must resolve to the same ObserverStateStore instance as :global_state
        container.register_factory(:state_store) { |c| c.resolve(:global_state) }

        # Library scanner service
        container.register_factory(:library_scanner) do |_c|
          EbookReader::Services::LibraryScanner.new
        end

        container
      end

      def self.create_test_container
        require 'rspec/mocks'

        container = DependencyContainer.new

        # Mock services for testing
        container.register(:event_bus,
                           RSpec::Mocks::Double.new('EventBus', subscribe: nil, emit_event: nil))
        container.register(:state_store,
                           RSpec::Mocks::Double.new('StateStore', get: nil, set: nil,
                                                                  current_state: {}))
        container.register(:logger,
                           RSpec::Mocks::Double.new('Logger', info: nil, error: nil, debug: nil))

        # Provide a domain event bus backed by the mocked infrastructure bus
        container.register(:domain_event_bus, Domain::Events::DomainEventBus.new(container.resolve(:event_bus)))

        container
      end
    end
  end
end
