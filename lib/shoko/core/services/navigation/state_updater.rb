# frozen_string_literal: true

module Shoko
  module Core
    module Services
      module Navigation
        # Applies state updates using the most appropriate state_store API.
        class StateUpdater
          def initialize(state_store)
            @state_store = state_store
          end

          def apply(updates)
            return if updates.nil? || updates.empty?

            can_update = @state_store.respond_to?(:update)
            can_set = @state_store.respond_to?(:set)

            if can_update && (!can_set || updates.length > 1)
              @state_store.update(updates)
            elsif can_set
              updates.each { |path, value| @state_store.set(path, value) }
            end
          end
        end
      end
    end
  end
end
