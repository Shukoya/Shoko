# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(config)
          case config.view_mode
          when :split
            SplitViewRenderer.new
          else
            SingleViewRenderer.new(config.page_numbering_mode)
          end
        end
      end
    end
  end
end
