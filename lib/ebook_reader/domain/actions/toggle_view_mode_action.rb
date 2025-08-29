# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Toggle reader view between :split and :single
      class ToggleViewModeAction < BaseAction
        def apply(state)
          current = state.get(%i[config view_mode]) || :split
          new_mode = current == :split ? :single : :split
          state.update(%i[config view_mode], new_mode)

          # Nudge layout recalculation on next render
          state.update(%i[reader last_width], 0)
          state.update(%i[reader last_height], 0)
          state.update(%i[reader dynamic_page_map], nil)
          state.update(%i[reader dynamic_total_pages], 0)
          state.update(%i[reader last_dynamic_width], 0)
          state.update(%i[reader last_dynamic_height], 0)

          new_mode
        end
      end
    end
  end
end

