# frozen_string_literal: true

module EbookReader
  class MainMenu
    # Encapsulates loading-state updates while a book is preprocessed.
    class MenuProgressPresenter
      def initialize(state)
        @state = state
      end

      def show(path:, index:, mode:)
        dispatch(
          loading_active: true,
          loading_path: path,
          loading_progress: 0.0,
          loading_index: index,
          loading_mode: mode
        )
      end

      def update(done:, total:)
        progress = EbookReader::Application::ProgressHelper.ratio(done, total)
        dispatch(loading_progress: progress)
      end

      def clear
        dispatch(
          loading_active: false,
          loading_path: nil,
          loading_progress: nil,
          loading_index: nil,
          loading_mode: nil
        )
      end

      private

      def dispatch(payload)
        @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(payload))
      end
    end
  end
end
