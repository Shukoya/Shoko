# frozen_string_literal: true

require_relative '../infrastructure/background_worker'
require_relative '../infrastructure/atomic_file_writer'
require_relative '../infrastructure/performance_monitor'
require_relative '../infrastructure/perf_tracer'
require_relative '../infrastructure/pagination_cache'
require_relative '../infrastructure/cache_paths'
require_relative '../infrastructure/epub_cache'
require_relative '../infrastructure/kitty_image_renderer'
require_relative '../infrastructure/gutendex_client'
require_relative '../infrastructure/repositories/cached_library_repository'
require_relative '../infrastructure/parsers/xhtml_content_parser'
require_relative '../infrastructure/render_registry'
require_relative 'services/cache_service'
require_relative 'services/file_writer_service'
require_relative 'services/instrumentation_service'
require_relative 'services/path_service'
require_relative 'services/download_service'

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
        container.register(:performance_monitor, Infrastructure::PerformanceMonitor)
        container.register(:perf_tracer, Infrastructure::PerfTracer)
        container.register(:pagination_cache, Infrastructure::PaginationCache)
        container.register(:cache_paths, Infrastructure::CachePaths)
        container.register(:atomic_file_writer, Infrastructure::AtomicFileWriter)
        container.register(:epub_cache_factory, ->(path) { Infrastructure::EpubCache.new(path) })
        container.register(:epub_cache_predicate, ->(path) { Infrastructure::EpubCache.cache_file?(path) })
        container.register_singleton(:gutendex_client) do |c|
          Infrastructure::GutendexClient.new(logger: c.resolve(:logger))
        end
        container.register(:background_worker_factory,
                           lambda do |name: 'reader-worker'|
                             Infrastructure::BackgroundWorker.new(name:)
                           end)
        container.register(:xhtml_parser_factory,
                           lambda do |raw|
                             Infrastructure::Parsers::XHTMLContentParser.new(raw)
                           end)

        # Domain event bus (eagerly capture event_bus to avoid repeated resolves)
        eb = container.resolve(:event_bus)
        container.register_singleton(:domain_event_bus) { |_c| Domain::Events::DomainEventBus.new(eb) }

        # Domain repositories
        container.register_factory(:bookmark_repository) { |c| Domain::Repositories::BookmarkRepository.new(c) }
        container.register_factory(:annotation_repository) { |c| Domain::Repositories::AnnotationRepository.new(c) }
        container.register_factory(:progress_repository) { |c| Domain::Repositories::ProgressRepository.new(c) }
        container.register_factory(:config_repository) { |c| Domain::Repositories::ConfigRepository.new(c) }
        container.register_factory(:recent_library_repository) do |c|
          Domain::Repositories::RecentLibraryRepository.new(c)
        end

        # Domain services with dependency injection
        container.register_factory(:navigation_service) { |c| Domain::Services::NavigationService.new(c) }
        container.register_factory(:bookmark_service) { |c| Domain::Services::BookmarkService.new(c) }
        container.register_singleton(:page_calculator) { |c| Domain::Services::PageCalculatorService.new(c) }
        container.register_factory(:coordinate_service) { |c| Domain::Services::CoordinateService.new(c) }
        container.register_factory(:selection_service) { |c| Domain::Services::SelectionService.new(c) }
        container.register_factory(:layout_service) { |c| Domain::Services::LayoutService.new(c) }
        container.register_factory(:clipboard_service) { |c| Domain::Services::ClipboardService.new(c) }
        # TerminalService wraps a global Terminal; use a singleton to keep lifecycle consistent
        container.register_singleton(:terminal_service) { |c| Domain::Services::TerminalService.new(c) }
        container.register_factory(:annotation_service) { |c| Domain::Services::AnnotationService.new(c) }
        container.register_factory(:library_service) { |c| Domain::Services::LibraryService.new(c) }
        container.register_factory(:catalog_service) { |c| Domain::Services::CatalogService.new(c) }
        container.register_factory(:download_service) { |c| Domain::Services::DownloadService.new(c) }
        # WrappingService caches windows/chapters; make it a singleton to share cache
        container.register_singleton(:wrapping_service) { |c| Domain::Services::WrappingService.new(c) }
        container.register_singleton(:formatting_service) { |c| Domain::Services::FormattingService.new(c) }
        container.register_factory(:settings_service) { |c| Domain::Services::SettingsService.new(c) }
        container.register_singleton(:kitty_image_renderer) { |_c| Infrastructure::KittyImageRenderer.new }

        container.register_singleton(:cache_service) { |c| Domain::Services::CacheService.new(c) }
        container.register_singleton(:file_writer) { |c| Domain::Services::FileWriterService.new(c) }
        container.register_singleton(:instrumentation_service) { |c| Domain::Services::InstrumentationService.new(c) }
        container.register_singleton(:path_service) { |c| Domain::Services::PathService.new(c) }

        container.register_factory(:pagination_cache_preloader) do |c|
          EbookReader::Application::PaginationCachePreloader.new(
            state: c.resolve(:global_state),
            page_calculator: c.resolve(:page_calculator),
            pagination_cache: c.resolve(:pagination_cache)
          )
        end

        # Notifications
        container.register_singleton(:notification_service) { |c| Domain::Services::NotificationService.new(c) }

        # Document service factory (per-book instance)
        container.register_factory(:document_service_factory) do |c|
          lambda do |path, progress_reporter: nil|
            wrapper = c.resolve(:wrapping_service)
            formatting = c.resolve(:formatting_service)
            worker = c.registered?(:background_worker) ? c.resolve(:background_worker) : nil
            klass = Infrastructure::DocumentService
            instantiate_document_service(klass, path, wrapper, formatting, worker, progress_reporter)
          end
        end

        # Render registry keeps large per-frame geometry out of state store
        container.register_singleton(:render_registry) { |_c| Infrastructure::RenderRegistry.current }

        # Focused controllers replacing god class

        # Unified state management
        container.register_singleton(:global_state) { |_c| Infrastructure::ObserverStateStore.new(eb) }

        # IMPORTANT: state_store must resolve to the same ObserverStateStore instance as :global_state
        container.register_factory(:state_store) { |c| c.resolve(:global_state) }

        # Library scanner service (infrastructure)
        container.register_singleton(:cached_library_repository) do |_c|
          EbookReader::Infrastructure::Repositories::CachedLibraryRepository.new
        end

        container.register_factory(:library_scanner) do |_c|
          EbookReader::Infrastructure::LibraryScanner.new
        end

        if defined?(EbookReader::TestSupport::TestMode)
          EbookReader::TestSupport::TestMode.configure_container(container)
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
        container.register(:atomic_file_writer, Infrastructure::AtomicFileWriter)
        container.register(:cache_paths, Infrastructure::CachePaths)
        container.register(:epub_cache_factory, ->(path) { Infrastructure::EpubCache.new(path) })
        container.register(:epub_cache_predicate, ->(path) { Infrastructure::EpubCache.cache_file?(path) })
        container.register(:file_writer, Domain::Services::FileWriterService.new(container))
        container.register(:path_service, Domain::Services::PathService.new(container))
        container.register(:instrumentation_service, Domain::Services::InstrumentationService.new(container))

        # Provide a domain event bus backed by the mocked infrastructure bus
        container.register(:domain_event_bus, Domain::Events::DomainEventBus.new(container.resolve(:event_bus)))

        if defined?(EbookReader::TestSupport::TestMode)
          EbookReader::TestSupport::TestMode.configure_container(container)
        end

        container
      end

      def self.instantiate_document_service(klass, path, wrapper, formatting, worker, progress_reporter = nil)
        klass.new(
          path,
          wrapper,
          formatting_service: formatting,
          background_worker: worker,
          progress_reporter: progress_reporter
        )
      rescue ArgumentError
        begin
          klass.new(path, wrapper, formatting_service: formatting, progress_reporter: progress_reporter)
        rescue ArgumentError
          begin
            klass.new(path, wrapper, progress_reporter: progress_reporter)
          rescue ArgumentError
            klass.new(path)
          end
        end
      end
    end
  end
end
