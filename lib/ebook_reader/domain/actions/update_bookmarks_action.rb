# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating the bookmarks list
      class UpdateBookmarksAction < BaseAction
        def initialize(bookmarks)
          super(bookmarks: bookmarks)
        end

        def apply(state)
          state.update({ %i[reader bookmarks] => payload[:bookmarks] })
        end
      end
    end
  end
end
