# frozen_string_literal: true

require_relative '../domain/actions/update_selection_action'
require_relative '../domain/selectors/reader_selectors'

module EbookReader
  module Application
    # Adapter exposing the annotation editor overlay through the same interface as
    # the legacy screen component so Domain commands can drive it via the input
    # dispatcher.
    class AnnotationEditorOverlaySession
      def initialize(state, dependencies, ui_controller)
        @state = state
        @dependencies = dependencies
        @ui_controller = ui_controller
      end

      def active?
        overlay = current_overlay
        overlay.respond_to?(:visible?) && overlay.visible?
      end

      def save_annotation
        overlay = current_overlay
        return :pass unless overlay

        annotation_service = resolve_annotation_service
        book_path = @ui_controller.current_book_path if @ui_controller.respond_to?(:current_book_path)

        unless annotation_service && book_path
          cancel_annotation
          return :pass
        end

        begin
          if overlay.annotation_id
            annotation_service.update(book_path, overlay.annotation_id, overlay.note)
            @ui_controller.set_message('Annotation updated', 2)
          else
            annotation_service.add(book_path,
                                   overlay.selected_text,
                                   overlay.note,
                                   overlay.selection_range,
                                   overlay.chapter_index,
                                   nil)
            @ui_controller.set_message('Annotation saved!', 2)
          end
          @ui_controller.refresh_annotations if @ui_controller.respond_to?(:refresh_annotations)
        rescue StandardError => e
          @ui_controller.set_message("Save failed: #{e.message}", 3)
        ensure
          close_overlay
          clear_selection
        end
        :handled
      end

      def cancel_annotation
        close_overlay
        clear_selection
        @ui_controller.set_message('Annotation cancelled', 2)
        :handled
      end

      def handle_backspace
        overlay = current_overlay
        overlay&.handle_backspace
        :handled
      end

      def handle_enter
        overlay = current_overlay
        overlay&.handle_enter if overlay.respond_to?(:handle_enter)
        :handled
      end

      def handle_character(char)
        overlay = current_overlay
        overlay&.handle_character(char) if overlay.respond_to?(:handle_character)
        :handled
      end

      private

      def current_overlay
        EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
      end

      def resolve_annotation_service
        return unless @dependencies.respond_to?(:resolve)

        @dependencies.resolve(:annotation_service)
      rescue StandardError
        nil
      end

      def close_overlay
        return unless @ui_controller

        begin
          @ui_controller.send(:close_annotation_editor_overlay)
        rescue StandardError
          nil
        end
      end

      def clear_selection
        @state.dispatch(EbookReader::Domain::Actions::ClearSelectionAction.new)
      rescue StandardError
        nil
      end
    end
  end
end
