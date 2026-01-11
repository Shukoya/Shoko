# frozen_string_literal: true

require_relative 'base_action'

require_relative 'update_field_helpers'

module Shoko
  module Application
    module Actions
      # Action to update pagination-related reader state in a single, consistent way.
      # Allowed fields: :page_map, :total_pages, :last_width, :last_height, :total_chapters
      class UpdatePaginationStateAction < BaseAction
        ALLOWED = %i[page_map total_pages last_width last_height total_chapters].freeze

        def apply(state)
          UpdateFieldHelpers.apply_allowed(state, payload, ALLOWED, namespace: :reader)
        end
      end
    end
  end
end
