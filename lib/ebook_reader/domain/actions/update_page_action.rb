# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Action for updating page positions (current_page_index, left_page, right_page, single_page)
      class UpdatePageAction < BaseAction
        def apply(state)
          # Build update hash for atomic state update
          updates = {}
          payload.each do |page_field, value|
            updates[[:reader, page_field]] = value
          end
          state.update(updates)
        end
      end
    end
  end
end
