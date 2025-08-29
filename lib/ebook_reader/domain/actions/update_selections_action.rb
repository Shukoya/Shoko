# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating various selection states
      class UpdateSelectionsAction < BaseAction
        def initialize(updates)
          # Accepts hash like: { toc_selected: 2, bookmark_selected: 1 }
          super(updates)
        end

        def apply(state)
          payload.each do |field, value|
            state.update([:reader, field], value)
          end
        end
      end
    end
  end
end
