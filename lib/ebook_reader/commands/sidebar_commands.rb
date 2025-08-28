# frozen_string_literal: true

require_relative 'base_command'

module EbookReader
  module Commands
    # Commands for managing sidebar panel functionality
    class SidebarCommand < BaseCommand
      def initialize(action)
        @action = action
      end

      def can_execute?(context)
        context.respond_to?(:state) &&
          context.state.respond_to?(:sidebar_visible)
      end

      def description
        "Sidebar: #{@action}"
      end

      protected

      def perform(context, _key = nil)
        case @action
        when :toggle_sidebar
          toggle_sidebar(context)
        when :sidebar_switch_to_toc
          switch_tab(context, :toc)
        when :sidebar_switch_to_annotations
          switch_tab(context, :annotations)
        when :sidebar_switch_to_bookmarks
          switch_tab(context, :bookmarks)
        when :sidebar_navigate_up
          navigate_sidebar(context, :up)
        when :sidebar_navigate_down
          navigate_sidebar(context, :down)
        when :sidebar_activate_item
          activate_sidebar_item(context)
        when :sidebar_cycle_tab_forward
          cycle_tabs(context, :forward)
        when :sidebar_cycle_tab_backward
          cycle_tabs(context, :backward)
        when :sidebar_start_filter
          start_filter(context)
        when :sidebar_edit_annotation
          edit_annotation(context)
        when :sidebar_delete_item
          delete_item(context)
        else
          :pass
        end
      end

      private

      def toggle_sidebar(context)
        state = context.state
        new_visible = !state.sidebar_visible
        state.sidebar_visible = new_visible

        # Force single-page mode when sidebar is visible
        if new_visible && context.config.view_mode == :split
          context.config.view_mode = :single
          context.config.save
          force_content_refresh(context)
        end

        :handled
      end

      def switch_tab(context, tab)
        state = context.state

        # If sidebar not visible, show it and switch to tab
        unless state.sidebar_visible
          state.sidebar_visible = true
          if context.config.view_mode == :split
            context.config.view_mode = :single
            context.config.save
            force_content_refresh(context)
          end
        end

        state.sidebar_active_tab = tab
        :handled
      end

      def navigate_sidebar(context, direction)
        state = context.state
        return :pass unless state.sidebar_visible

        case state.sidebar_active_tab
        when :toc
          navigate_toc(state, direction)
        when :annotations
          navigate_annotations(state, direction)
        when :bookmarks
          navigate_bookmarks(state, direction)
        end

        :handled
      end

      def navigate_toc(state, direction)
        current = state.sidebar_toc_selected || 0
        # We'd need access to the document to get chapter count
        # For now, let's assume a reasonable range
        max_chapters = 50 # This should be passed from context

        case direction
        when :up
          state.sidebar_toc_selected = [current - 1, 0].max
        when :down
          state.sidebar_toc_selected = [current + 1, max_chapters - 1].min
        end
      end

      def navigate_annotations(state, direction)
        current = state.sidebar_annotations_selected || 0
        # Similar constraint - we'd need annotation count
        max_annotations = 100

        case direction
        when :up
          state.sidebar_annotations_selected = [current - 1, 0].max
        when :down
          state.sidebar_annotations_selected = [current + 1, max_annotations - 1].min
        end
      end

      def navigate_bookmarks(state, direction)
        current = state.sidebar_bookmarks_selected || 0
        bookmarks = state.bookmarks || []
        return if bookmarks.empty?

        case direction
        when :up
          state.sidebar_bookmarks_selected = [current - 1, 0].max
        when :down
          state.sidebar_bookmarks_selected = [current + 1, bookmarks.length - 1].min
        end
      end

      def activate_sidebar_item(context)
        state = context.state
        return :pass unless state.sidebar_visible

        case state.sidebar_active_tab
        when :toc
          activate_toc_item(context)
        when :annotations
          activate_annotation_item(context)
        when :bookmarks
          activate_bookmark_item(context)
        end

        :handled
      end

      def activate_toc_item(context)
        selected = context.state.sidebar_toc_selected || 0
        context.jump_to_chapter(selected) if context.respond_to?(:jump_to_chapter)
      end

      def activate_annotation_item(context)
        # Implementation depends on annotation structure
        # This would jump to the annotation location
      end

      def activate_bookmark_item(context)
        bookmarks = context.state.bookmarks || []
        selected = context.state.sidebar_bookmarks_selected || 0
        return unless selected < bookmarks.length

        bookmark = bookmarks[selected]
        return unless bookmark && context.respond_to?(:jump_to_bookmark)

        context.state.bookmark_selected = selected
        context.jump_to_bookmark
      end

      def cycle_tabs(context, direction)
        state = context.state
        return :pass unless state.sidebar_visible

        tabs = %i[toc annotations bookmarks]
        current_index = tabs.index(state.sidebar_active_tab) || 0

        case direction
        when :forward
          new_index = (current_index + 1) % tabs.length
        when :backward
          new_index = (current_index - 1) % tabs.length
        end

        state.sidebar_active_tab = tabs[new_index]
        :handled
      end

      def start_filter(context)
        state = context.state
        return :pass unless state.sidebar_visible && state.sidebar_active_tab == :toc

        state.sidebar_toc_filter_active = true
        state.sidebar_toc_filter = ''
        :handled
      end

      def edit_annotation(_context)
        # Implementation for editing annotation
        :pass
      end

      def delete_item(context)
        state = context.state
        return :pass unless state.sidebar_visible

        case state.sidebar_active_tab
        when :annotations
          # Delete selected annotation
        when :bookmarks
          # Delete selected bookmark
          context.delete_selected_bookmark if context.respond_to?(:delete_selected_bookmark)
        end

        :handled
      end

      def force_content_refresh(context)
        # Force re-render of content component
        return unless context.respond_to?(:force_redraw)

        context.force_redraw
      end
    end
  end
end
