# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Domain-level facade for annotation persistence and state updates.
      # Centralizes access to the underlying store and ensures UI state is refreshed
      # via UpdateAnnotationsAction after mutations.
      class AnnotationService < BaseService
        def list_for_book(path)
          return [] unless path && !path.to_s.empty?

          EbookReader::Annotations::AnnotationStore.get(path) || []
        end

        def list_all
          EbookReader::Annotations::AnnotationStore.all || {}
        end

        def add(path, text, note, range, chapter_index, page_meta = nil)
          EbookReader::Annotations::AnnotationStore.add(path, text, note, range, chapter_index,
                                                        page_meta)
          notify_updated(path)
          true
        end

        def update(path, id, note)
          EbookReader::Annotations::AnnotationStore.update(path, id, note)
          notify_updated(path)
          true
        end

        def delete(path, id)
          EbookReader::Annotations::AnnotationStore.delete(path, id)
          notify_updated(path)
          true
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
        end

        private

        def notify_updated(path)
          return unless @state_store && path

          annotations = list_for_book(path)
          @state_store.dispatch(EbookReader::Domain::Actions::UpdateAnnotationsAction.new(annotations))
        rescue StandardError
          # Best-effort state refresh; persistence already succeeded
          nil
        end
      end
    end
  end
end
