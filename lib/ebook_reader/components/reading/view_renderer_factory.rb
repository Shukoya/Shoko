# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(state, controller = nil)
          case Domain::Selectors::ConfigSelectors.view_mode(state)
          when :split
            SplitViewRenderer.new(nil, controller)
          else
            SingleViewRenderer.new(Domain::Selectors::ConfigSelectors.page_numbering_mode(state), nil, controller)
          end
        end
      end
    end
  end
end
