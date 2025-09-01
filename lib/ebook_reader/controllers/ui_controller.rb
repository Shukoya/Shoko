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

      def switch_mode(mode, **options)
        @state.update({[:reader, :mode] => mode})

        case mode
        when :annotation_editor
          @current_mode = ReaderModes::AnnotationEditorMode.new(self, **options)
        when :annotations
          @current_mode = ReaderModes::AnnotationsMode.new(self)
        when :read, :help, :toc, :bookmarks
          @current_mode = nil
        when :popup_menu
          # Popup handled separately via @state.get([:reader, :popup_menu])
        else
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
        # Toggle sidebar TOC panel at ~30% width and keep main view in read mode
        begin
          if @state.get([:reader, :sidebar_visible]) && @state.get([:reader, :sidebar_active_tab]) == :toc
            # Closing TOC sidebar – restore previous view mode if stored
            prev_mode = @state.get([:reader, :sidebar_prev_view_mode])
            if prev_mode
              @state.update({[:config, :view_mode] => prev_mode})
              @state.update({[:reader, :sidebar_prev_view_mode] => nil})
            end
            @state.update({[:reader, :sidebar_visible] => false})
            @state.update({[:reader, :mode] => :read})
            set_message('TOC closed', 1)
          else
            # Opening TOC sidebar – store current view and force single-page view
            @state.update({[:reader, :sidebar_prev_view_mode] => @state.get([:config, :view_mode])})
            @state.update({[:config, :view_mode] => :single})

            @state.update({
              [:reader, :sidebar_active_tab] => :toc,
              [:reader, :sidebar_toc_selected] => @state.get([:reader, :current_chapter]),
              [:reader, :sidebar_visible] => true,
              [:reader, :mode] => :read
            })
            set_message('TOC opened', 1)
          end
        rescue StandardError => e
          set_message("TOC error: #{e.message}", 3)
        end
      end

      def open_bookmarks
        switch_mode(:bookmarks)
        @state.update({[:reader, :bookmark_selected] => 0})
      end

      def open_annotations
        switch_mode(:annotations)
      end

      def show_help
        switch_mode(:help)
      end

      def toggle_view_mode
        current_mode = @state.get([:config, :view_mode])
        new_mode = current_mode == :split ? :single : :split
        @state.update({[:config, :view_mode] => new_mode})
      end

      def increase_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get([:config, :line_spacing])) || 1
        return unless current < 2

        @state.update({[:config, :line_spacing] => modes[current + 1]})
        @state.update({[:reader, :last_width] => 0})
      end

      def decrease_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get([:config, :line_spacing])) || 1
        return unless current.positive?

        @state.update({[:config, :line_spacing] => modes[current - 1]})
        @state.update({[:reader, :last_width] => 0})
      end

      def toggle_page_numbering_mode
        current_mode = @state.get([:config, :page_numbering_mode])
        new_mode = current_mode == :absolute ? :dynamic : :absolute
        @state.update({[:config, :page_numbering_mode] => new_mode})
        set_message("Page numbering: #{new_mode}")
      end

      # Sidebar navigation helpers
      def sidebar_down
        return unless @state.get([:reader, :sidebar_visible])

        case @state.get([:reader, :sidebar_active_tab])
        when :toc
          max = (@dependencies.resolve(:document)&.chapters&.length || 1) - 1
          current = @state.get([:reader, :sidebar_toc_selected]) || 0
          @state.update({[:reader, :sidebar_toc_selected] => [current + 1, [max, 0].max].min})
        when :annotations
          max = (@state.get([:reader, :annotations]) || []).length - 1
          current = @state.get([:reader, :sidebar_annotations_selected]) || 0
          @state.update({[:reader, :sidebar_annotations_selected] => [current + 1, [max, 0].max].min})
        when :bookmarks
          max = (@state.get([:reader, :bookmarks]) || []).length - 1
          current = @state.get([:reader, :sidebar_bookmarks_selected]) || 0
          @state.update({[:reader, :sidebar_bookmarks_selected] => [current + 1, [max, 0].max].min})
        end
      end

      def sidebar_up
        return unless @state.get([:reader, :sidebar_visible])

        case @state.get([:reader, :sidebar_active_tab])
        when :toc
          current = @state.get([:reader, :sidebar_toc_selected]) || 0
          @state.update({[:reader, :sidebar_toc_selected] => [current - 1, 0].max})
        when :annotations
          current = @state.get([:reader, :sidebar_annotations_selected]) || 0
          @state.update({[:reader, :sidebar_annotations_selected] => [current - 1, 0].max})
        when :bookmarks
          current = @state.get([:reader, :sidebar_bookmarks_selected]) || 0
          @state.update({[:reader, :sidebar_bookmarks_selected] => [current - 1, 0].max})
        end
      end

      def sidebar_select
        return unless @state.get([:reader, :sidebar_visible])

        case @state.get([:reader, :sidebar_active_tab])
        when :toc
          index = @state.get([:reader, :sidebar_toc_selected]) || 0
          # Delegate to navigation controller
          @dependencies.resolve(:navigation_controller).jump_to_chapter(index)

          # Close the sidebar and restore previous view mode if it was stored
          prev_mode = @state.get([:reader, :sidebar_prev_view_mode])
          if prev_mode
            @state.update({[:config, :view_mode] => prev_mode})
            @state.update({[:reader, :sidebar_prev_view_mode] => nil})
          end
          @state.update({[:reader, :sidebar_visible] => false})
          @state.update({[:reader, :mode] => :read})
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
        @state.update({[:reader, :popup_menu] => nil})
        @state.update({[:reader, :selection] => nil})
      end

      # Refresh annotations from persistence into state
      def refresh_annotations
        begin
          state_controller = @dependencies.resolve(:state_controller)
          state_controller.refresh_annotations if state_controller.respond_to?(:refresh_annotations)
        rescue StandardError
          # Best-effort; ignore failures silently here
        end
      end

      # Provide current book path for modes/components that need persistence context
      def current_book_path
        @state.get(%i[reader book_path])
      end

      def set_message(text, duration = 2)
        @state.update({[:reader, :message] => text})
        Thread.new do
          sleep duration
          @state.update({[:reader, :message] => nil})
        end
      end

      attr_reader :current_mode

      private

      def handle_create_annotation_action(action_data)
        selection_range = action_data.is_a?(Hash) ? action_data[:data][:selection_range] : @state.get([:reader, :selection])
        # Extract selected text from the controller that manages it
        selected_text = extract_selected_text_from_selection(selection_range)
        switch_mode(:read)
        switch_mode(:annotation_editor,
                   text: selected_text,
                   range: selection_range,
                   chapter_index: @state.get([:reader, :current_chapter]))
      end

      def handle_copy_to_clipboard_action(_action_data)
        clipboard_service = @dependencies.resolve(:clipboard_service)
        # Get selected text from current selection
        selection = @state.get([:reader, :selection])
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
        return '' unless selection_range
        selection_service = @dependencies.resolve(:selection_service)
        rendered_lines = @state.get([:reader, :rendered_lines]) || {}
        selection_service.extract_text(selection_range, rendered_lines)
      end
    end
  end
end
