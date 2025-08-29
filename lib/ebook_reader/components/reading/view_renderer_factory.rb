# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(state)
          case Domain::Selectors::ConfigSelectors.view_mode(state)
          when :split
            SplitViewRenderer.new
          else
            SingleViewRenderer.new(Domain::Selectors::ConfigSelectors.page_numbering_mode(state))
          end
        end
      end
    end
  end
end
