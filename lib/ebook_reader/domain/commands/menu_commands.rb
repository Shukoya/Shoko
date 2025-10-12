# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Menu commands for top-level and browse screens
      class MenuCommand < BaseCommand
        def initialize(action)
          @action = action
          super(name: "menu_#{action}", description: "Menu action #{action}")
        end

        def can_execute?(context, _params = {})
          context.respond_to?(:state) && (context.respond_to?(:dependencies) || true)
        end

        protected

        def perform(context, _params = {})
          state = context.state
          mmc = context.respond_to?(:main_menu_component) ? context.main_menu_component : nil
          can_switch = context.respond_to?(:switch_to_mode)
          case @action
          when :menu_up then update_menu_index(context, :selected, -1, 0, 5)
          when :menu_down then update_menu_index(context, :selected, +1, 0, 5)
          when :menu_select then context.handle_menu_selection if context.respond_to?(:handle_menu_selection)
          when :menu_quit then context.cleanup_and_exit(0, '') if context.respond_to?(:cleanup_and_exit)
          when :back_to_menu then switch_mode(context, :menu, can_switch)
          when :browse_up then browse_nav(context, -1)
          when :browse_down then browse_nav(context, +1)
          when :browse_select then context.open_selected_book if context.respond_to?(:open_selected_book)
          when :library_up then context.library_up if context.respond_to?(:library_up)
          when :library_down then context.library_down if context.respond_to?(:library_down)
          when :library_select then context.library_select if context.respond_to?(:library_select)
          when :toggle_view_mode then context.toggle_view_mode if context.respond_to?(:toggle_view_mode)
          when :cycle_line_spacing then context.cycle_line_spacing if context.respond_to?(:cycle_line_spacing)
          when :toggle_page_numbers then context.toggle_page_numbers if context.respond_to?(:toggle_page_numbers)
          when :toggle_page_numbering_mode
            context.toggle_page_numbering_mode if context.respond_to?(:toggle_page_numbering_mode)
          when :toggle_highlight_quotes
            context.toggle_highlight_quotes if context.respond_to?(:toggle_highlight_quotes)
          when :wipe_cache then context.wipe_cache if context.respond_to?(:wipe_cache)
          when :start_search
            if context.respond_to?(:switch_to_search)
              context.switch_to_search
            else
              # Fallback: set mode/search_active via actions
              state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :search,
                                                                                search_active: true))
            end
            current = (state.get(%i[menu search_query]) || '').to_s
            state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(search_cursor: current.length))
          when :exit_search
            if context.respond_to?(:switch_to_browse)
              context.switch_to_browse
            else
              state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :browse,
                                                                                search_active: false))
            end
          # recent_* actions removed
          # Annotations list (menu) actions
          when :annotations_up
            mmc&.annotations_screen&.navigate(:up)
          when :annotations_down
            mmc&.annotations_screen&.navigate(:down)
          when :annotations_select
            if mmc
              screen = mmc.annotations_screen
              ann = screen.current_annotation
              path = screen.current_book_path
              if ann && path
                state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(
                                 selected_annotation: ann,
                                 selected_annotation_book: path
                               ))
                switch_mode(context, :annotation_detail, can_switch)
              end
            end
          when :annotations_edit, :annotation_detail_edit
            context.open_selected_annotation_for_edit if context.respond_to?(:open_selected_annotation_for_edit)
          when :annotations_delete, :annotation_detail_delete
            delete_selected_annotation_if_available(context, can_switch)
          # Annotation detail actions
          when :annotation_detail_open
            context.open_selected_annotation if context.respond_to?(:open_selected_annotation)
          when :annotation_detail_back
            switch_mode(context, :annotations, can_switch)
          else
            :pass
          end
        end

        private

        def switch_mode(context, mode, can_switch)
          context.switch_to_mode(mode) if can_switch
        end

        def delete_selected_annotation_if_available(context, can_switch)
          return unless context.respond_to?(:delete_selected_annotation)

          context.delete_selected_annotation
          switch_mode(context, :annotations, can_switch)
        end

        def update_menu_index(context, field, delta, min_idx, max_idx)
          state = context.state
          current = state.get([:menu, field]) || 0
          new_val = (current + delta).clamp(min_idx, max_idx)
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(field => new_val))
          new_val
        end

        def browse_nav(context, delta)
          state = context.state
          # Prefer component's filtered list length; fall back to public accessor
          mmc = context.respond_to?(:main_menu_component) ? context.main_menu_component : nil
          max_idx = if mmc.respond_to?(:browse_screen)
                      cnt = mmc.browse_screen.filtered_count
                      [(cnt || 0) - 1, 0].max
                    else
                      epubs = (context.respond_to?(:filtered_epubs) && context.filtered_epubs) || []
                      [epubs.length - 1, 0].max
                    end

          current = state.get(%i[menu browse_selected]) || 0
          new_val = (current + delta).clamp(0, max_idx)
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: new_val))
          new_val
        end

        # recent navigation removed
      end
    end
  end
end
