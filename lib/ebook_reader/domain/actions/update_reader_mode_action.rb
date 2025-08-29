# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating the reader mode (read, help, toc, bookmarks, etc.)
      class UpdateReaderModeAction < BaseAction
        def initialize(new_mode)
          super(mode: new_mode)
        end

        def apply(state)
          state.update(%i[reader mode], payload[:mode])
        end
      end
    end
  end
end