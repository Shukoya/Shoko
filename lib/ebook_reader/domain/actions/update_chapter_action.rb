# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating the current chapter
      class UpdateChapterAction < BaseAction
        def initialize(chapter_index)
          super(chapter_index: chapter_index)
        end

        def apply(state)
          state.update({ %i[reader current_chapter] => payload[:chapter_index] })
        end
      end
    end
  end
end
