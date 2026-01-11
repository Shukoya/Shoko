# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Application
    module Actions
      # Action for updating UI loading indicators
      # Accepts any of: :loading_active, :loading_message, :loading_progress
      class UpdateUILoadingAction < BaseAction
        def apply(state)
          updates = {}
          payload.each do |field, value|
            next unless %i[loading_active loading_message loading_progress].include?(field)

            updates[[:ui, field]] = value
          end
          state.update(updates) unless updates.empty?
        end
      end
    end
  end
end
