# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      class SplitRenderer
        def initialize(component)
          @component = component
        end

        def render(surface, bounds)
          @component.send(:render_split, surface, bounds)
        end
      end
    end
  end
end
