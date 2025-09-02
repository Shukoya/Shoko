# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating menu-related state under [:menu, *]
      class UpdateMenuAction < BaseAction
        # Payload is a hash of menu_field => value
        def apply(state)
          updates = {}
          payload.each do |field, value|
            updates[[:menu, field]] = value
          end
          state.update(updates)
        end
      end
    end
  end
end
