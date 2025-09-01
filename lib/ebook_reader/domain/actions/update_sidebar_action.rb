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
          # Build update hash for atomic state update
          updates = {}
          payload.each do |field, value|
            case field
            when :visible
              updates[[:reader, :sidebar_visible]] = value
            when :active_tab
              updates[[:reader, :sidebar_active_tab]] = value
            when :toc_selected
              updates[[:reader, :sidebar_toc_selected]] = value
            when :annotations_selected
              updates[[:reader, :sidebar_annotations_selected]] = value
            when :bookmarks_selected
              updates[[:reader, :sidebar_bookmarks_selected]] = value
            end
          end
          state.update(updates)
        end
      end
    end
  end
end
