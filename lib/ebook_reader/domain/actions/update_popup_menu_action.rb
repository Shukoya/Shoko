# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Action for updating popup menu state
      class UpdatePopupMenuAction < BaseAction
        def initialize(popup_menu)
          super(popup_menu: popup_menu)
        end

        def apply(state)
          state.update({ %i[reader popup_menu] => payload[:popup_menu] })
        end
      end

      # Convenience action for clearing popup menu
      class ClearPopupMenuAction < UpdatePopupMenuAction
        def initialize
          super(nil)
        end
      end
    end
  end
end
