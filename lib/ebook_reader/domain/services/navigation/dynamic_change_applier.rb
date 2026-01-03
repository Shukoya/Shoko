# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Navigation
        # Applies dynamic-mode changes to the state store.
        class DynamicChangeApplier
          def initialize(state_store:, page_calculator:, state_updater:)
            @state_store = state_store
            @page_calculator = page_calculator
            @state_updater = state_updater
          end

          def apply(changes)
            return if changes.nil? || changes.empty?

            update_page_index(changes[:current_page_index]) if changes.key?(:current_page_index)

            return unless changes.key?(:current_chapter)

            @state_updater.apply(%i[reader current_chapter] => changes[:current_chapter])
          end

          private

          def update_page_index(new_index)
            updates = { %i[reader current_page_index] => new_index }
            page = @page_calculator&.get_page(new_index)
            if page
              current_chapter = page[:chapter_index]
              current_chapter ||= current_chapter_from_state || 0
              updates[%i[reader current_chapter]] = current_chapter
            end

            @state_updater.apply(updates)
          end

          def current_chapter_from_state
            return nil unless @state_store.respond_to?(:current_state)

            @state_store.current_state.dig(:reader, :current_chapter)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
