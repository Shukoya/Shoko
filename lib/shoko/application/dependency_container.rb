# frozen_string_literal: true

require 'set'
require_relative '../adapters/storage/background_worker.rb'
require_relative '../adapters/storage/atomic_file_writer.rb'
require_relative '../adapters/monitoring/performance_monitor.rb'
require_relative '../adapters/monitoring/perf_tracer.rb'
require_relative '../adapters/storage/pagination_cache.rb'
require_relative '../adapters/storage/cache_paths.rb'
require_relative '../adapters/storage/epub_cache.rb'
require_relative '../adapters/output/kitty/kitty_image_renderer.rb'
require_relative '../adapters/book_sources/gutendex_client.rb'
require_relative '../adapters/storage/repositories/cached_library_repository.rb'
require_relative '../adapters/book_sources/epub/parsers/xhtml_content_parser.rb'
require_relative '../adapters/output/render_registry.rb'
require_relative '../core/events/domain_event_bus'
require_relative '../adapters/storage/file_writer_service'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/book_sources/download_service'

module Shoko
  module Application
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
        container.register_singleton(:event_bus) { Application::Infrastructure::EventBus.new }
        container.register_singleton(:logger) { Adapters::Monitoring::Logger }
        container.register(:performance_monitor, Adapters::Monitoring::PerformanceMonitor)
        container.register(:perf_tracer, Adapters::Monitoring::PerfTracer)
        container.register(:pagination_cache, Adapters::Storage::PaginationCache)
        container.register(:cache_paths, Adapters::Storage::CachePaths)
        container.register(:atomic_file_writer, Adapters::Storage::AtomicFileWriter)
        container.register(:epub_cache_factory, ->(path) { Adapters::Storage::EpubCache.new(path) })
        container.register(:epub_cache_predicate, ->(path) { Adapters::Storage::EpubCache.cache_file?(path) })
        container.register_singleton(:gutendex_client) do |c|
          Adapters::BookSources::GutendexClient.new(logger: c.resolve(:logger))
        end
        container.register(:background_worker_factory,
                           lambda do |name: 'shoko-worker'|
                             Adapters::Storage::BackgroundWorker.new(name:)
                           end)
        container.register(:xhtml_parser_factory,
                           lambda do |raw|
                             Adapters::BookSources::Epub::Parsers::XHTMLContentParser.new(raw)
                           end)

        # Domain event bus (eagerly capture event_bus to avoid repeated resolves)
        eb = container.resolve(:event_bus)
        container.register_singleton(:domain_event_bus) do |_c|
          Core::Events::DomainEventBus.new(eb)
        end

        # Repository implementations (infrastructure)
        container.register_factory(:bookmark_repository) { |c| Adapters::Storage::Repositories::BookmarkRepository.new(c) }
        container.register_factory(:annotation_repository) { |c| Adapters::Storage::Repositories::AnnotationRepository.new(c) }
        container.register_factory(:progress_repository) { |c| Adapters::Storage::Repositories::ProgressRepository.new(c) }
        container.register_factory(:config_repository) { |c| Adapters::Storage::Repositories::ConfigRepository.new(c) }
        # Domain services with dependency injection
        container.register_factory(:navigation_service) { |c| Core::Services::NavigationService.new(c) }
        container.register_factory(:bookmark_service) { |c| Core::Services::BookmarkService.new(c) }
        container.register_singleton(:page_calculator) { |c| Core::Services::PageCalculatorService.new(c) }
        container.register_factory(:coordinate_service) { |c| Core::Services::CoordinateService.new(c) }
        container.register_factory(:selection_service) { |c| Core::Services::SelectionService.new(c) }
        container.register_factory(:layout_service) { |c| Core::Services::LayoutService.new(c) }
        container.register_factory(:clipboard_service) { |c| Adapters::Output::Clipboard::ClipboardService.new(c) }
        # TerminalService wraps a global Terminal; use a singleton to keep lifecycle consistent
        container.register_singleton(:terminal_service) { |c| Adapters::Output::Terminal::TerminalService.new(c) }
        container.register_factory(:annotation_service) { |c| Core::Services::AnnotationService.new(c) }
        container.register_factory(:catalog_service) { |c| Application::UseCases::CatalogService.new(c) }
        container.register_factory(:download_service) { |c| Adapters::BookSources::DownloadService.new(c) }
        # WrappingService caches windows/chapters; make it a singleton to share cache
        container.register_singleton(:wrapping_service) { |c| Adapters::Output::Formatting::WrappingService.new(c) }
        container.register_singleton(:formatting_service) { |c| Adapters::Output::Formatting::FormattingService.new(c) }
        container.register_factory(:settings_service) { |c| Application::UseCases::SettingsService.new(c) }
        container.register_singleton(:kitty_image_renderer) { |_c| Adapters::Output::Kitty::KittyImageRenderer.new }

        container.register_singleton(:file_writer) { |c| Adapters::Storage::FileWriterService.new(c) }
        container.register_singleton(:instrumentation_service) { |c| Adapters::Output::InstrumentationService.new(c) }

        container.register_factory(:pagination_cache_preloader) do |c|
          Shoko::Core::Services::Pagination::PaginationCachePreloader.new(
            state: c.resolve(:global_state),
            page_calculator: c.resolve(:page_calculator),
            pagination_cache: c.resolve(:pagination_cache)
          )
        end

        # Notifications
        container.register_singleton(:notification_service) { |c| Adapters::Output::NotificationService.new(c) }

        # Document service factory (per-book instance)
        container.register_factory(:document_service_factory) do |c|
          lambda do |path, progress_reporter: nil|
            wrapper = c.resolve(:wrapping_service)
            formatting = c.resolve(:formatting_service)
            worker = c.registered?(:background_worker) ? c.resolve(:background_worker) : nil
            klass = Adapters::BookSources::DocumentService
            instantiate_document_service(klass, path, wrapper, formatting, worker, progress_reporter)
          end
        end

        # Render registry keeps large per-frame geometry out of state store
        container.register_singleton(:render_registry) { |_c| Adapters::Output::RenderRegistry.current }

        # Focused controllers replacing god class

        # Unified state management
        container.register_singleton(:global_state) { |_c| Application::Infrastructure::ObserverStateStore.new(eb) }

        # IMPORTANT: state_store must resolve to the same ObserverStateStore instance as :global_state
        container.register_factory(:state_store) { |c| c.resolve(:global_state) }

        # Library scanner service (infrastructure)
        container.register_singleton(:cached_library_repository) do |_c|
          Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new
        end

        container.register_factory(:library_scanner) do |_c|
          Shoko::Adapters::BookSources::LibraryScanner.new
        end

        if defined?(Shoko::TestSupport::TestMode)
          Shoko::TestSupport::TestMode.configure_container(container)
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
        container.register(:atomic_file_writer, Adapters::Storage::AtomicFileWriter)
        container.register(:cache_paths, Adapters::Storage::CachePaths)
        container.register(:epub_cache_factory, ->(path) { Adapters::Storage::EpubCache.new(path) })
        container.register(:epub_cache_predicate, ->(path) { Adapters::Storage::EpubCache.cache_file?(path) })
        container.register(:file_writer, Adapters::Storage::FileWriterService.new(container))
        container.register(:instrumentation_service, Adapters::Output::InstrumentationService.new(container))

        # Provide a domain event bus backed by the mocked infrastructure bus
        container.register(:domain_event_bus,
                           Core::Events::DomainEventBus.new(container.resolve(:event_bus)))

        if defined?(Shoko::TestSupport::TestMode)
          Shoko::TestSupport::TestMode.configure_container(container)
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
