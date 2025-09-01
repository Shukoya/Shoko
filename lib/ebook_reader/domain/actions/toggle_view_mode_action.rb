# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Toggle reader view between :split and :single
      class ToggleViewModeAction < BaseAction
        def apply(state)
          current = state.get([:config, :view_mode]) || :split
          new_mode = current == :split ? :single : :split
          
          # Update all state changes atomically
          state.update({
            [:config, :view_mode] => new_mode,
            [:reader, :last_width] => 0,
            [:reader, :last_height] => 0,
            [:reader, :dynamic_page_map] => nil,
            [:reader, :dynamic_total_pages] => 0,
            [:reader, :last_dynamic_width] => 0,
            [:reader, :last_dynamic_height] => 0
          })

          new_mode
        end
      end
    end
  end
end

