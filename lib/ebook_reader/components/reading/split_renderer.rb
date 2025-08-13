# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Reading
      class SplitRenderer < BaseComponent
        def initialize(content_component)
          super()
          @content_component = content_component
        end

        def do_render(surface, bounds)
          @content_component.send(:render_split, surface, bounds)
        end

        def preferred_height(available_height)
          available_height
        end
      end
    end
  end
end
