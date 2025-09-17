# frozen_string_literal: true

module EbookReader
  module Controllers
    # Handles all UI-related functionality: modes, overlays, popups, sidebar
    class UIController
      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @current_mode = nil
      end

      def switch_mode(mode, **)
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
        toggle_sidebar(:annotations)
      end

      private

      # Unified sidebar toggling for :toc, :annotations, :bookmarks
      def toggle_sidebar(tab)
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
          updates[:toc_selected] = @state.get(%i[reader current_chapter])
        when :annotations
          updates[:annotations_selected] =
            @state.get(%i[reader sidebar_annotations_selected]) || 0
        when :bookmarks
          updates[:bookmarks_selected] =
            @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        end

        @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(updates))
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
          index = @state.get(%i[reader sidebar_toc_selected]) || 0
          # Use domain navigation service consistently
          nav_service = @dependencies.resolve(:navigation_service)
          nav_service.jump_to_chapter(index)

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

        cleanup_popup_state
      end

      def cleanup_popup_state
        @state.dispatch(EbookReader::Domain::Actions::ClearPopupMenuAction.new)
        @state.dispatch(EbookReader::Domain::Actions::ClearSelectionAction.new)
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

      def update_sidebar_selection(delta)
        return unless sidebar_visible?

        tab = @state.get(%i[reader sidebar_active_tab])
        key, action_key, max = case tab
                               when :toc
                                 doc = @dependencies.resolve(:document)
                                 indices = navigable_toc_indices_for(doc)
                                 cur = @state.get(%i[reader sidebar_toc_selected]) || indices.first || 0
                                 target = if delta.positive?
                                            indices.find { |idx| idx > cur } || indices.last || cur
                                          elsif delta.negative?
                                            indices.reverse.find { |idx| idx < cur } || indices.first || cur
                                          else
                                            cur
                                          end
                                 updates = { sidebar_toc_selected: target, toc_selected: target }
                                 @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(updates))
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

      def navigable_toc_indices_for(doc)
        entries = if doc.respond_to?(:toc_entries)
                    Array(doc.toc_entries)
                  else
                    []
                  end
        indices = entries.map(&:chapter_index).compact.uniq.sort
        if indices.empty?
          chapters_count = doc&.chapters&.length.to_i
          (0...chapters_count).to_a
        else
          indices
        end
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
        switch_mode(:read)
        switch_mode(:annotation_editor,
                    text: selected_text,
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
          set_message('Failed to copy to clipboard') unless success
        else
          set_message('Copy to clipboard not available')
        end
        switch_mode(:read)
      end

      # Extract selected text from selection range using SelectionService
      def extract_selected_text_from_selection(selection_range)
        selection_service = @dependencies.resolve(:selection_service)
        if selection_service.respond_to?(:extract_from_state)
          selection_service.extract_from_state(@state, selection_range)
        else
          rendered_lines = @state.get(%i[reader rendered_lines]) || {}
          selection_service.extract_text(selection_range, rendered_lines)
        end
      end
    end
  end
end
