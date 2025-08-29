# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Base action for immutable-like state updates via GlobalState#dispatch
      class BaseAction
        def initialize(payload = {})
          @payload = payload
        end

        # Apply the action to the given GlobalState instance
        # Implement in subclasses
        def apply(_state)
          raise NotImplementedError, 'Action subclasses must implement #apply(state)'
        end

        protected

        attr_reader :payload
      end
    end
  end
end

