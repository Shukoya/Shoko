# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Action for updating the reader mode
      class UpdateModeAction < BaseAction
        def initialize(mode)
          super(mode: mode)
        end

        def apply(state)
          state.update({ %i[reader mode] => payload[:mode] })
        end
      end
    end
  end
end
