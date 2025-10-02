# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Updates the reader annotations overlay component stored in state.
      class UpdateAnnotationsOverlayAction < BaseAction
        def initialize(overlay)
          super(overlay: overlay)
        end

        def apply(state)
          state.update({ %i[reader annotations_overlay] => payload[:overlay] })
        end
      end

      # Clears any active annotations overlay.
      class ClearAnnotationsOverlayAction < UpdateAnnotationsOverlayAction
        def initialize
          super(nil)
        end
      end
    end
  end
end
