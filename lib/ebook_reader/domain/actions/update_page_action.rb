# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating page positions (current_page_index, left_page, right_page, single_page)
      class UpdatePageAction < BaseAction
        def initialize(page_updates)
          # Expects hash like: { current_page_index: 5, left_page: 10, right_page: 11 }
          super(page_updates)
        end

        def apply(state)
          payload.each do |page_field, value|
            state.update([:reader, page_field], value)
          end
        end
      end
    end
  end
end