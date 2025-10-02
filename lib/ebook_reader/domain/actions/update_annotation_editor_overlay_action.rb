# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Stores the annotation editor overlay component in state.
      class UpdateAnnotationEditorOverlayAction < BaseAction
        def initialize(overlay)
          super(overlay: overlay)
        end

        def apply(state)
          state.update({ %i[reader annotation_editor_overlay] => payload[:overlay] })
        end
      end

      # Clears any active annotation editor overlay from state.
      class ClearAnnotationEditorOverlayAction < UpdateAnnotationEditorOverlayAction
        def initialize
          super(nil)
        end
      end
    end
  end
end
