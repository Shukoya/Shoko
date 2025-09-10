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
          case @action
          when :menu_up then update_menu_index(context, :selected, -1, 0, 5)
          when :menu_down then update_menu_index(context, :selected, +1, 0, 5)
          when :menu_select then if context.respond_to?(:handle_menu_selection)
                                   context.handle_menu_selection
                                 end
          when :menu_quit then if context.respond_to?(:cleanup_and_exit)
                                 context.cleanup_and_exit(0,
                                                          '')
                               end
          when :back_to_menu then if context.respond_to?(:switch_to_mode)
                                    context.switch_to_mode(:menu)
                                  end
          when :browse_up then browse_nav(context, -1)
          when :browse_down then browse_nav(context, +1)
          when :browse_select then if context.respond_to?(:open_selected_book)
                                     context.open_selected_book
                                   end
          when :start_search
            if context.respond_to?(:switch_to_search)
              context.switch_to_search
            else
              # Fallback: set mode/search_active via actions
              context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :search,
                                                                                        search_active: true))
            end
            current = (context.state.get(%i[menu search_query]) || '').to_s
            context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(search_cursor: current.length))
          when :exit_search
            if context.respond_to?(:switch_to_browse)
              context.switch_to_browse
            else
              context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :browse,
                                                                                        search_active: false))
            end
          # recent_* actions removed
          # Annotations list (menu) actions
          when :annotations_up
            if context.respond_to?(:main_menu_component)
              context.main_menu_component.annotations_screen.navigate(:up)
            end
          when :annotations_down
            if context.respond_to?(:main_menu_component)
              context.main_menu_component.annotations_screen.navigate(:down)
            end
          when :annotations_select
            if context.respond_to?(:main_menu_component)
              ann = context.main_menu_component.annotations_screen.current_annotation
              path = context.main_menu_component.annotations_screen.current_book_path
              if ann && path
                context.state.update({
                                       %i[menu selected_annotation] => ann,
                                       %i[menu selected_annotation_book] => path,
                                     })
                context.switch_to_mode(:annotation_detail) if context.respond_to?(:switch_to_mode)
              end
            end
          when :annotations_edit
            if context.respond_to?(:open_selected_annotation_for_edit)
              context.open_selected_annotation_for_edit
            end
          when :annotations_delete
            context.delete_selected_annotation if context.respond_to?(:delete_selected_annotation)
          # Annotation detail actions
          when :annotation_detail_open
            context.open_selected_annotation if context.respond_to?(:open_selected_annotation)
          when :annotation_detail_edit
            if context.respond_to?(:open_selected_annotation_for_edit)
              context.open_selected_annotation_for_edit
            end
          when :annotation_detail_delete
            if context.respond_to?(:delete_selected_annotation)
              context.delete_selected_annotation
              context.switch_to_mode(:annotations) if context.respond_to?(:switch_to_mode)
            end
          when :annotation_detail_back
            context.switch_to_mode(:annotations) if context.respond_to?(:switch_to_mode)
          else
            :pass
          end
        end

        private

        def update_menu_index(context, field, delta, min_idx, max_idx)
          state = context.state
          current = state.get([:menu, field]) || 0
          new_val = [[current + delta, min_idx].max, max_idx].min
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(field => new_val))
          new_val
        end

        def browse_nav(context, delta)
          state = context.state
          # Prefer component's filtered list length; fall back to public accessor
          max_idx = if context.respond_to?(:main_menu_component) && context.main_menu_component.respond_to?(:browse_screen)
                      cnt = context.main_menu_component.browse_screen.filtered_count
                      [(cnt || 0) - 1, 0].max
                    else
                      epubs = (context.respond_to?(:filtered_epubs) && context.filtered_epubs) || []
                      [epubs.length - 1, 0].max
                    end

          current = state.get(%i[menu browse_selected]) || 0
          new_val = [[current + delta, 0].max, max_idx].min
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: new_val))
          new_val
        end

        # recent navigation removed
      end
    end
  end
end
