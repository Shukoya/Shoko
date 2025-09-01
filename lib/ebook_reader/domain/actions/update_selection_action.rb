# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating text selection state
      class UpdateSelectionAction < BaseAction
        def initialize(selection)
          super(selection: selection)
        end

        def apply(state)
          state.update({[:reader, :selection] => payload[:selection]})
        end
      end

      # Convenience action for clearing selection
      class ClearSelectionAction < UpdateSelectionAction
        def initialize
          super(nil)
        end
      end
    end
  end
end