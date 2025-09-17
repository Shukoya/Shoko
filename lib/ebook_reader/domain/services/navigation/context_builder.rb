# frozen_string_literal: true

require_relative 'nav_context'
require_relative 'context_helpers'

module EbookReader
  module Domain
    module Services
      module Navigation
        # Builds navigation context snapshots from the current state.
        class ContextBuilder
          def initialize(state_store, page_calculator)
            @state_store = state_store
            @page_calculator = page_calculator
          end

          def build
            snapshot = ContextHelpers.safe_snapshot(@state_store)

            NavContext.new(
              mode: ContextHelpers.dynamic_mode?(snapshot) ? :dynamic : :absolute,
              view_mode: ContextHelpers.current_view_mode(snapshot),
              current_chapter: ContextHelpers.current_chapter(snapshot),
              total_chapters: ContextHelpers.total_chapters(snapshot),
              current_page_index: ContextHelpers.current_page_index(snapshot),
              dynamic_total_pages: dynamic_total_pages,
              single_page: ContextHelpers.single_page(snapshot),
              left_page: ContextHelpers.left_page(snapshot),
              right_page: ContextHelpers.right_page(snapshot),
              max_page_in_chapter: 0
            )
          end

          private

          attr_reader :page_calculator

          def dynamic_total_pages
            return 0 unless page_calculator&.respond_to?(:total_pages)

            page_calculator.total_pages.to_i
          rescue StandardError
            0
          end
        end
      end
    end
  end
end
