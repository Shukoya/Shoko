# frozen_string_literal: true

module EbookReader
  module Domain
    module Selectors
      # Selectors for menu state - provides read-only access to state
      module MenuSelectors
        def self.selected(state)
          state.get(%i[menu selected])
        end

        def self.selected_item(state)
          selected(state)
        end

        def self.mode(state)
          state.get(%i[menu mode])
        end

        def self.browse_selected(state)
          state.get(%i[menu browse_selected])
        end

        def self.search_query(state)
          state.get(%i[menu search_query]) || ''
        end

        def self.search_cursor(state)
          state.get(%i[menu search_cursor])
        end

        def self.file_input(state)
          state.get(%i[menu file_input]) || ''
        end

        def self.search_active(state)
          state.get(%i[menu search_active])
        end

        def self.search_active?(state)
          search_active(state)
        end
      end
    end
  end
end
