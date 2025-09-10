# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/annotation_events'

module EbookReader
  module Domain
    module Services
      # Domain-level service for annotation persistence and state updates.
      # Uses AnnotationRepository for clean separation from infrastructure.
      class AnnotationService < BaseService
        def list_for_book(path)
          return [] unless path && !path.to_s.empty?

          @annotation_repository.find_by_book_path(path)
        end

        def list_all
          @annotation_repository.find_all
        end

        def add(path, text, note, range, chapter_index, page_meta = nil)
          annotation = @annotation_repository.add_for_book(
            path,
            text: text,
            note: note,
            range: range,
            chapter_index: chapter_index,
            page_meta: page_meta
          )

          # Publish domain event
          @domain_event_bus.publish(Events::AnnotationAdded.new(
                                      book_path: path,
                                      annotation: annotation
                                    ))

          notify_updated(path)
          annotation
        end

        def update(path, id, note)
          # Get old annotation for event (optional, repository might not support find_by_id in tests)
          old_note = ''
          if @annotation_repository.respond_to?(:find_by_id)
            old_annotation = @annotation_repository.find_by_id(path, id)
            old_note = old_annotation ? old_annotation['note'] : ''
          end

          @annotation_repository.update_note(path, id, note)

          # Publish domain event
          @domain_event_bus.publish(Events::AnnotationUpdated.new(
                                      book_path: path,
                                      annotation_id: id,
                                      old_note: old_note,
                                      new_note: note
                                    ))

          notify_updated(path)
          true
        end

        def delete(path, id)
          # Get annotation for event before deletion (optional)
          annotation = nil
          if @annotation_repository.respond_to?(:find_by_id)
            annotation = @annotation_repository.find_by_id(path,
                                                           id)
          end

          @annotation_repository.delete_by_id(path, id)

          # Publish domain event
          @domain_event_bus.publish(Events::AnnotationRemoved.new(
                                      book_path: path,
                                      annotation_id: id,
                                      annotation: annotation
                                    ))

          notify_updated(path)
          true
        end

        protected

        def required_dependencies
          %i[state_store annotation_repository domain_event_bus]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @annotation_repository = resolve(:annotation_repository)
          @domain_event_bus = resolve(:domain_event_bus)
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
