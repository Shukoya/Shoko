# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(state, controller = nil)
          case Domain::Selectors::ConfigSelectors.view_mode(state)
          when :split
            # Always pass the app dependencies to ensure a single DI source
            SplitViewRenderer.new(controller&.dependencies, controller)
          else
            SingleViewRenderer.new(Domain::Selectors::ConfigSelectors.page_numbering_mode(state),
                                   controller&.dependencies, controller)
          end
        end
      end
    end
  end
end
