# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Application
    module Actions
      # Action for updating annotations list
      class UpdateAnnotationsAction < BaseAction
        def initialize(annotations)
          super(annotations: annotations)
        end

        def apply(state)
          state.update({ %i[reader annotations] => payload[:annotations] })
        end
      end
    end
  end
end
