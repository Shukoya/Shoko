# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating various selection states
      class UpdateSelectionsAction < BaseAction
        def apply(state)
          # Build update hash for atomic state update
          updates = {}
          payload.each do |field, value|
            updates[[:reader, field]] = value
          end
          state.update(updates)
        end
      end
    end
  end
end
