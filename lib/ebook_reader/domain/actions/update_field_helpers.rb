# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      module UpdateFieldHelpers
        module_function

        # Apply only allowed fields under a namespaced state path
        # e.g., namespace = :reader results in updates to [:reader, field]
        def apply_allowed(state, payload, allowed, namespace: :reader)
          updates = {}
          payload.each do |field, value|
            next unless allowed.include?(field)
            updates[[namespace, field]] = value
          end
          state.update(updates) unless updates.empty?
        end
      end
    end
  end
end

