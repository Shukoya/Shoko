# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      class SingleRenderer
        def initialize(component)
          @component = component
        end

        def render(surface, bounds)
          @component.send(:render_single_absolute, surface, bounds)
        end
      end
    end
  end
end
