# frozen_string_literal: true

module EbookReader
  module Services
    # Central registry for service instances to enable dependency injection
    # and eliminate scattered service instantiation throughout components
    class ServiceRegistry
      class << self
        def initialize_services(controller)
          @services = {
            layout: LayoutService,
            coordinate: CoordinateService,
            clipboard: ClipboardService,
            navigation: NavigationService.new(controller),
            bookmark: BookmarkService.new(controller),
            state: StateService.new(controller),
          }
        end

        def get(service_name)
          @services ||= {}
          service = @services[service_name.to_sym]

          unless service
            Infrastructure::Logger.warn("Service not found: #{service_name}")
            return nil
          end

          service
        end

        def register(service_name, instance)
          @services ||= {}
          @services[service_name.to_sym] = instance
        end

        def clear
          @services = {}
        end

        # Convenience methods for commonly used services
        def layout
          get(:layout)
        end

        def coordinate
          get(:coordinate)
        end

        def clipboard
          get(:clipboard)
        end

        def navigation
          get(:navigation)
        end

        def bookmark
          get(:bookmark)
        end

        def state
          get(:state)
        end
      end
    end
  end
end
