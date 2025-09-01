# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating the status message
      class UpdateMessageAction < BaseAction
        def initialize(message)
          super(message: message)
        end

        def apply(state)
          state.update({[:reader, :message] => payload[:message]})
        end
      end

      # Convenience action for clearing message
      class ClearMessageAction < UpdateMessageAction
        def initialize
          super(nil)
        end
      end
    end
  end
end