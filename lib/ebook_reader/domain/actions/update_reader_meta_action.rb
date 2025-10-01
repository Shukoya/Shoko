# frozen_string_literal: true

require_relative 'base_action'

require_relative 'update_field_helpers'

module EbookReader
  module Domain
    module Actions
      # Action to update reader meta fields that are not pagination specific
      # Allowed fields: :book_path, :running
      class UpdateReaderMetaAction < BaseAction
        ALLOWED = %i[book_path running].freeze

        def apply(state)
          UpdateFieldHelpers.apply_allowed(state, payload, ALLOWED, namespace: :reader)
        end
      end
    end
  end
end
