# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Reading
      class SingleRenderer < BaseComponent
        def initialize(content_component)
          super()
          @content_component = content_component
        end

        def do_render(surface, bounds)
          @content_component.send(:render_single_absolute, surface, bounds)
        end

        def preferred_height(available_height)
          available_height
        end
      end
    end
  end
end
