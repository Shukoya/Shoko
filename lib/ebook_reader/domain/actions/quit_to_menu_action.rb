# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Stop the reader loop (used to return to menu)
      class QuitToMenuAction < BaseAction
        def apply(state)
          state.update({ %i[reader running] => false })
        end
      end
    end
  end
end
