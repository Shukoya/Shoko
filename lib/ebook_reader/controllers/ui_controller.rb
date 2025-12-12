# frozen_string_literal: true

require_relative '../components/annotations_overlay_component'
require_relative '../components/annotation_editor_overlay_component'

module EbookReader
  module Controllers
    # Handles all UI-related functionality: modes, overlays, popups, sidebar
    class UIController
      class MissingDependencyError < StandardError; end

      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @current_mode = nil
      end

      def switch_mode(mode, **)
        close_annotations_overlay unless mode == :annotation_editor
        close_annotation_editor_overlay unless mode == :annotation_editor
        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(mode))

        if mode == :annotation_editor
          @current_mode = Components::Screens::AnnotationEditorScreenComponent.new(self, **,
                                                                                   dependencies: @dependencies)
        else
          # Rendered via screen/sidebar components; no standalone mode component
          @current_mode = nil
        end

        # Keep input dispatcher in sync with mode to prevent cross-mode key leaks
        begin
          input_controller = @dependencies.resolve(:input_controller)
          input_controller.activate_for_mode(mode) if input_controller.respond_to?(:activate_for_mode)
        rescue StandardError
          # If not available, ignore; read mode remains default
        end
      end

      def open_toc
        toggle_sidebar(:toc)
      rescue StandardError => e
        set_message("TOC error: #{e.message}", 3)
      end

      def open_bookmarks
        switch_mode(:bookmarks)
        @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: 0))
      end

      def open_annotations
        overlay = Domain::Selectors::ReaderSelectors.annotations_overlay(@state)
        if overlay&.visible?
          close_annotations_overlay
        else
          show_annotations_overlay
        end
      end

      def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        show_annotation_editor_overlay(text: text,
                                       range: range,
                                       chapter_index: chapter_index,
                                       annotation: annotation)
      end

      private

      # Unified sidebar toggling for :toc, :annotations, :bookmarks
      def toggle_sidebar(tab)
        close_annotations_overlay
        if sidebar_open_for?(tab)
          close_sidebar_with_restore(tab)
        else
          open_sidebar_for(tab)
        end
      end

      def sidebar_open_for?(tab)
        @state.get(%i[reader sidebar_visible]) &&
          @state.get(%i[reader sidebar_active_tab]) == tab
      end

      def close_sidebar_with_restore(tab)
        prev_mode = @state.get(%i[reader sidebar_prev_view_mode])
        if prev_mode
          @state.dispatch(
            EbookReader::Domain::Actions::UpdateConfigAction.new(view_mode: prev_mode)
          )
          @state.dispatch(
            EbookReader::Domain::Actions::UpdateSelectionsAction.new(sidebar_prev_view_mode: nil)
          )
        end
        @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(visible: false))
        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
        set_message("#{tab.to_s.capitalize} closed", 1)
      end

      def open_sidebar_for(tab)
        # Store current view and force single-page view
        @state.dispatch(
          EbookReader::Domain::Actions::UpdateSelectionsAction.new(
            sidebar_prev_view_mode: @state.get(%i[config view_mode])
          )
        )
        @state.dispatch(
          EbookReader::Domain::Actions::UpdateConfigAction.new(view_mode: :single)
        )

        updates = { active_tab: tab, visible: true }
        case tab
        when :toc
          doc = safe_resolve(:document)
          entries = toc_entries_for(doc)
          current_chapter = (@state.get(%i[reader current_chapter]) || 0).to_i
          updates[:toc_selected] = toc_index_for_chapter(entries, current_chapter)
        when :annotations
          updates[:annotations_selected] =
            @state.get(%i[reader sidebar_annotations_selected]) || 0
        when :bookmarks
          updates[:bookmarks_selected] =
            @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        end

        @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(updates))
        if tab == :toc
          selected = updates[:toc_selected].to_i
          @state.dispatch(
            EbookReader::Domain::Actions::UpdateSelectionsAction.new(
              toc_selected: selected,
              sidebar_toc_selected: selected
            )
          )
        end
        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
        set_message("#{tab.to_s.capitalize} opened", 1)
      end

      public

      def show_help
        switch_mode(:help)
      end

      def toggle_view_mode
        @state.dispatch(EbookReader::Domain::Actions::ToggleViewModeAction.new)
      end

      def increase_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current < 2

        @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(line_spacing: modes[current + 1]))
        @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(last_width: 0))
      end

      def decrease_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current.positive?

        @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(line_spacing: modes[current - 1]))
        @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(last_width: 0))
      end

      def toggle_page_numbering_mode
        current_mode = @state.get(%i[config page_numbering_mode])
        new_mode = current_mode == :absolute ? :dynamic : :absolute
        @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(page_numbering_mode: new_mode))
        set_message("Page numbering: #{new_mode}")
      end

      # Sidebar navigation helpers
      def sidebar_down
        update_sidebar_selection(+1)
      end

      def sidebar_up
        update_sidebar_selection(-1)
      end

      def sidebar_select
        return unless sidebar_visible?

        case @state.get(%i[reader sidebar_active_tab])
        when :toc
          doc = safe_resolve(:document)
          entries = toc_entries_for(doc)
          selected_entry_index = (@state.get(%i[reader sidebar_toc_selected]) || 0).to_i
          selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)
          chapter_index = entries[selected_entry_index]&.chapter_index
          return unless chapter_index

          nav_service = @dependencies.resolve(:navigation_service)
          nav_service.jump_to_chapter(chapter_index)

          # Close the sidebar and restore previous view mode if it was stored
          prev_mode = @state.get(%i[reader sidebar_prev_view_mode])
          if prev_mode
            @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(view_mode: prev_mode))
            @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(sidebar_prev_view_mode: nil))
          end
          @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(visible: false))
          @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
        end
      end

      def handle_popup_action(action_data)
        # Handle both old string-based actions and new action objects
        action_type = action_data.is_a?(Hash) ? action_data[:action] : action_data

        case action_type
        when :create_annotation, 'Create Annotation'
          handle_create_annotation_action(action_data)
        when :copy_to_clipboard, 'Copy to Clipboard'
          handle_copy_to_clipboard_action(action_data)
        end

        skip_editor = %i[create_annotation].include?(action_type) || action_type == 'Create Annotation'
        cleanup_popup_state(skip_editor: skip_editor)
      end

      def cleanup_popup_state(skip_editor: false)
        @state.dispatch(EbookReader::Domain::Actions::ClearPopupMenuAction.new)
        @state.dispatch(EbookReader::Domain::Actions::ClearSelectionAction.new)
        close_annotations_overlay
        close_annotation_editor_overlay unless skip_editor
        # Also reset any mouse-driven selection held outside state (MouseableReader)
        begin
          reader_controller = @dependencies.resolve(:reader_controller)
          reader_controller&.send(:clear_selection!)
        rescue StandardError
          # Best-effort; ignore if not available
        end
      end

      # Refresh annotations from persistence into state
      def refresh_annotations
        state_controller = @dependencies.resolve(:state_controller)
        state_controller.refresh_annotations if state_controller.respond_to?(:refresh_annotations)
      rescue StandardError
        # Best-effort; ignore failures silently here
      end

      # Provide current book path for modes/components that need persistence context
      def current_book_path
        @state.get(%i[reader book_path])
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        # Fallback to direct dispatch if service not available
        @state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))
      end

      attr_reader :current_mode

      private

      def sidebar_visible?
        @state.get(%i[reader sidebar_visible])
      end

      def show_annotations_overlay
        overlay = Components::AnnotationsOverlayComponent.new(@state)
        @state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationsOverlayAction.new(overlay))
        set_message('Annotations overlay open (↑/↓ navigate, Enter open, e edit, d delete)', 3)
      rescue StandardError
        cleanup_annotations_overlay_fallback
      end

      def close_annotations_overlay
        overlay = Domain::Selectors::ReaderSelectors.annotations_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(EbookReader::Domain::Actions::ClearAnnotationsOverlayAction.new)
      rescue StandardError
        cleanup_annotations_overlay_fallback
      end

      def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        overlay = Components::AnnotationEditorOverlayComponent.new(
          selected_text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
        @state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))
        if activate_annotation_editor_overlay_session
          set_message('Annotation editor active (Ctrl+S save, Esc cancel)', 3)
        else
          cleanup_annotation_editor_overlay_fallback
          set_message('Annotation editor unavailable', 3)
        end
      rescue StandardError => e
        cleanup_annotation_editor_overlay_fallback
        log_dependency_error(:show_annotation_editor_overlay, e)
        set_message('Annotation editor unavailable', 3)
      end

      def close_annotation_editor_overlay
        overlay = Domain::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(EbookReader::Domain::Actions::ClearAnnotationEditorOverlayAction.new)
        deactivate_annotation_editor_overlay_session
      rescue StandardError
        cleanup_annotation_editor_overlay_fallback
      end

      def update_sidebar_selection(delta)
        return unless sidebar_visible?

        tab = @state.get(%i[reader sidebar_active_tab])
        key, action_key, max = case tab
                               when :toc
                                 doc = safe_resolve(:document)
                                 entries = toc_entries_for(doc)
                                 indices = navigable_toc_entry_indices(entries)
                                 cur = (@state.get(%i[reader sidebar_toc_selected]) || indices.first || 0).to_i
                                 target = if delta.positive?
                                            indices.find { |idx| idx > cur } || indices.last || cur
                                          elsif delta.negative?
                                            indices.reverse.find { |idx| idx < cur } || indices.first || cur
                                          else
                                            cur
                                          end
                                 @state.dispatch(
                                   EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                                     sidebar_toc_selected: target,
                                     toc_selected: target
                                   )
                                 )
                                 return
                               when :annotations
                                 cur = @state.get(%i[reader sidebar_annotations_selected]) || 0
                                 max = (@state.get(%i[reader annotations]) || []).length - 1
                                 [:sidebar_annotations_selected, :annotations_selected, max]
                               when :bookmarks
                                 cur = @state.get(%i[reader sidebar_bookmarks_selected]) || 0
                                 max = (@state.get(%i[reader bookmarks]) || []).length - 1
                                 [:sidebar_bookmarks_selected, :bookmarks_selected, max]
                               else
                                 [nil, nil, nil]
                               end
        return unless key && action_key

        current = @state.get([:reader, key]) || 0
        max0 = [max, 0].max
        new_val = (current + delta).clamp(0, max0)
        @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(action_key => new_val))
      end

      def toc_entries_for(doc)
        entries = doc.respond_to?(:toc_entries) ? Array(doc.toc_entries) : []
        return entries unless entries.empty?

        chapters = doc.respond_to?(:chapters) ? Array(doc.chapters) : []
        chapters.each_with_index.map do |chapter, idx|
          title = chapter.respond_to?(:title) ? chapter.title.to_s : ''
          title = "Chapter #{idx + 1}" if title.strip.empty?
          Domain::Models::TOCEntry.new(
            title: title,
            href: nil,
            level: 0,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      def navigable_toc_entry_indices(entries)
        indices = []
        Array(entries).each_with_index do |entry, idx|
          indices << idx if entry&.chapter_index
        end
        return indices unless indices.empty?

        (0...Array(entries).length).to_a
      end

      def toc_index_for_chapter(entries, chapter_index)
        Array(entries).find_index { |entry| entry&.chapter_index == chapter_index } || 0
      end

      def safe_resolve(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end

      def handle_create_annotation_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @state.get(%i[
                                         reader selection
                                       ])
                          end
        # Extract selected text from the controller that manages it
        selected_text = extract_selected_text_from_selection(selection_range)
        close_annotations_overlay
        show_annotation_editor_overlay(text: selected_text,
                                       range: selection_range,
                                       chapter_index: @state.get(%i[reader current_chapter]))
      end

      def handle_copy_to_clipboard_action(_action_data)
        clipboard_service = @dependencies.resolve(:clipboard_service)
        # Get selected text from current selection
        selection = @state.get(%i[reader selection])
        selected_text = extract_selected_text_from_selection(selection)

        if clipboard_service.available? && selected_text && !selected_text.strip.empty?
          success = clipboard_service.copy_with_feedback(selected_text) do |msg|
            set_message(msg)
          end
          set_message(' Failed to copy to clipboard') unless success
        else
          set_message(' Copy to clipboard not available')
        end
        switch_mode(:read)
      end

      # Extract selected text from selection range using SelectionService
      def extract_selected_text_from_selection(selection_range)
        selection_service = @dependencies.resolve(:selection_service)
        if selection_service.respond_to?(:extract_from_state)
          selection_service.extract_from_state(@state, selection_range)
        else
          rendered_lines = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(@state)
          selection_service.extract_text(selection_range, rendered_lines)
        end
      end

      def open_annotation_from_overlay(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        state_controller = @dependencies.resolve(:state_controller)
        state_controller.jump_to_annotation(normalized) if state_controller.respond_to?(:jump_to_annotation)
        close_annotations_overlay
      rescue StandardError
        close_annotations_overlay
      end

      def edit_annotation_from_overlay(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        close_annotations_overlay
        show_annotation_editor_overlay(text: normalized[:text],
                                       range: normalized[:range],
                                       chapter_index: normalized[:chapter_index],
                                       annotation: normalized)
      end

      def delete_annotation_from_overlay(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        state_controller = @dependencies.resolve(:state_controller)
        new_index = if state_controller.respond_to?(:delete_annotation_by_id)
                      state_controller.delete_annotation_by_id(normalized)
                    end

        overlay = Domain::Selectors::ReaderSelectors.annotations_overlay(@state)
        overlay.selected_index = new_index if overlay.respond_to?(:selected_index=) && !new_index.nil?

        annotations = @state.get(%i[reader annotations]) || []
        close_annotations_overlay if annotations.empty?
        set_message('Annotation deleted', 2)
      rescue StandardError
        close_annotations_overlay
      end

      def cleanup_annotations_overlay_fallback
        @state.dispatch(EbookReader::Domain::Actions::ClearAnnotationsOverlayAction.new)
      rescue StandardError
        nil
      end

      def normalize_annotation(annotation)
        return nil unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end

      def cleanup_annotation_editor_overlay_fallback
        @state.dispatch(EbookReader::Domain::Actions::ClearAnnotationEditorOverlayAction.new)
        deactivate_annotation_editor_overlay_session
      rescue StandardError
        nil
      end

      def handle_annotation_editor_overlay_event(result)
        overlay = Domain::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        case result[:type]
        when :save
          save_annotation_from_overlay(result[:note], overlay)
        when :cancel
          cancel_annotation_editor_overlay
        end
      end

      def save_annotation_from_overlay(note, overlay)
        svc = @dependencies.resolve(:annotation_service)
        path = current_book_path
        unless svc && path
          cancel_annotation_editor_overlay
          return
        end

        begin
          if overlay.annotation_id
            svc.update(path, overlay.annotation_id, note)
            set_message('Annotation updated', 2)
          else
            svc.add(path, overlay.selected_text, note, overlay.selection_range, overlay.chapter_index, nil)
            set_message('Annotation saved!', 2)
          end
          refresh_annotations
        rescue StandardError => e
          set_message("Save failed: #{e.message}", 3)
        ensure
          close_annotation_editor_overlay
          @state.dispatch(EbookReader::Domain::Actions::ClearSelectionAction.new)
        end
      end

      def cancel_annotation_editor_overlay
        close_annotation_editor_overlay
        set_message('Annotation cancelled', 2)
        @state.dispatch(EbookReader::Domain::Actions::ClearSelectionAction.new)
      end

      def activate_annotation_editor_overlay_session
        reader_controller = resolve_required(:reader_controller)
        input_controller = resolve_required(:input_controller)
        reader_controller.activate_annotation_editor_overlay_session
        input_controller.enter_modal_mode(:annotation_editor)
        true
      rescue MissingDependencyError => e
        log_dependency_error(:activate_annotation_editor_overlay_session, e)
        false
      end

      def deactivate_annotation_editor_overlay_session
        input_controller = resolve_optional(:input_controller)
        input_controller&.exit_modal_mode(:annotation_editor)
        reader_controller = resolve_optional(:reader_controller)
        reader_controller&.deactivate_annotation_editor_overlay_session
      end

      def safe_resolve(key)
        @dependencies.resolve(key)
      rescue StandardError
        nil
      end

      def resolve_required(key)
        service = @dependencies.resolve(key)
        raise MissingDependencyError, "Dependency :#{key} not registered" unless service

        service
      rescue MissingDependencyError
        raise
      rescue StandardError => e
        raise MissingDependencyError, "Dependency :#{key} failed to resolve: #{e.message}"
      end

      def resolve_optional(key)
        @dependencies.resolve(key)
      rescue StandardError
        nil
      end

      def log_dependency_error(context, error)
        logger = resolve_optional(:logger)
        return unless logger.respond_to?(:error)

        logger.error('Annotation editor activation failed', context: context, error: error.message)
      rescue StandardError
        nil
      end
    end
  end
end
