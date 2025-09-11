# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action to update pagination-related reader state in a single, consistent way.
      # Allowed fields: :page_map, :total_pages, :last_width, :last_height, :total_chapters
      class UpdatePaginationStateAction < BaseAction
        ALLOWED = %i[page_map total_pages last_width last_height total_chapters].freeze

        def apply(state)
          updates = {}
          payload.each do |field, value|
            next unless ALLOWED.include?(field)
            updates[[:reader, field]] = value
          end
          state.update(updates) unless updates.empty?
        end
      end
    end
  end
end

