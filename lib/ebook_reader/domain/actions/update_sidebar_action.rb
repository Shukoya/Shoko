# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating sidebar state
      class UpdateSidebarAction < BaseAction
        def initialize(updates)
          # Accepts hash like: { visible: true, active_tab: :toc, toc_selected: 5 }
          super(updates)
        end

        def apply(state)
          payload.each do |field, value|
            case field
            when :visible
              state.update([:reader, :sidebar_visible], value)
            when :active_tab
              state.update([:reader, :sidebar_active_tab], value)
            when :toc_selected
              state.update([:reader, :sidebar_toc_selected], value)
            when :annotations_selected
              state.update([:reader, :sidebar_annotations_selected], value)
            when :bookmarks_selected
              state.update([:reader, :sidebar_bookmarks_selected], value)
            end
          end
        end
      end
    end
  end
end
