# frozen_string_literal: true

module EbookReader
  module Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Geometry helper for the annotation editor overlay content region.
      class Geometry
        attr_reader :layout

        def initialize(layout)
          @layout = layout
        end

        def text_x
          layout.inner_x + 1
        end

        def text_width
          [layout.inner_width - 2, 1].max
        end

        def note_rows
          [layout.inner_height - 3, 1].max
        end

        def note_top
          layout.inner_y + 1
        end

        def buttons_row
          layout.inner_y + layout.inner_height - 2
        end

        def button_row_abs(bounds)
          bounds.y + buttons_row - 1
        end
      end
    end
  end
end
