# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Navigation
        module ContextHelpers
          module_function

          def safe_snapshot(state_store)
            return {} unless state_store.respond_to?(:current_state)

            state_store.current_state || {}
          rescue StandardError
            {}
          end

          def dynamic_mode?(snapshot)
            mode = snapshot.dig(:config, :page_numbering_mode)
            mode == :dynamic
          end

          def current_view_mode(snapshot)
            snapshot.dig(:config, :view_mode) || snapshot.dig(:reader, :view_mode) || :split
          end

          def current_chapter(snapshot)
            snapshot.dig(:reader, :current_chapter) || 0
          end

          def total_chapters(snapshot)
            snapshot.dig(:reader, :total_chapters) || 0
          end

          def current_page_index(snapshot)
            snapshot.dig(:reader, :current_page_index) || 0
          end

          def current_page(snapshot)
            snapshot.dig(:reader, :current_page) || 0
          end

          def single_page(snapshot)
            snapshot.dig(:reader, :single_page) || current_page(snapshot)
          end

          def left_page(snapshot)
            snapshot.dig(:reader, :left_page) || current_page(snapshot)
          end

          def right_page(snapshot)
            snapshot.dig(:reader, :right_page) || 0
          end

          def page_map(snapshot)
            snapshot.dig(:reader, :page_map) || []
          end
        end
      end
    end
  end
end
