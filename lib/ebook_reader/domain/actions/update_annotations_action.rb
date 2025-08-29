# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating annotations list
      class UpdateAnnotationsAction < BaseAction
        def initialize(annotations)
          super(annotations: annotations)
        end

        def apply(state)
          state.update([:reader, :annotations], payload[:annotations])
        end
      end
    end
  end
end