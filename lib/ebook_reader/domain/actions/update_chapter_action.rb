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
          idx = payload[:chapter_index]
          updates = {
            %i[reader current_chapter] => idx,
            %i[reader toc_selected] => idx,
            %i[reader sidebar_toc_selected] => idx,
          }
          state.update(updates)
        end
      end
    end
  end
end
