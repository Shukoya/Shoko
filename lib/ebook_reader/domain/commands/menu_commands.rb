# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Menu commands for top-level and browse/recent screens
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
          when :menu_select then context.handle_menu_selection if context.respond_to?(:handle_menu_selection)
          when :menu_quit then context.cleanup_and_exit(0, '') if context.respond_to?(:cleanup_and_exit)
          when :back_to_menu then context.switch_to_mode(:menu) if context.respond_to?(:switch_to_mode)
          when :browse_up then browse_nav(context, -1)
          when :browse_down then browse_nav(context, +1)
          when :browse_select then context.open_selected_book if context.respond_to?(:open_selected_book)
          when :start_search then
            if context.respond_to?(:switch_to_search)
              context.switch_to_search
            else
              # Fallback: set mode/search_active via actions
              context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :search,
                                                                                          search_active: true))
            end
            current = (context.state.get(%i[menu search_query]) || '').to_s
            context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(search_cursor: current.length))
          when :exit_search then
            if context.respond_to?(:switch_to_browse)
              context.switch_to_browse
            else
              context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :browse,
                                                                                           search_active: false))
            end
          when :recent_up then recent_nav(context, -1)
          when :recent_down then recent_nav(context, +1)
          when :recent_select then context.open_selected_recent_book if context.respond_to?(:open_selected_recent_book)
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
          # Prefer component's filtered list length if available
          max_idx = begin
            if context.respond_to?(:main_menu_component) && context.main_menu_component.respond_to?(:browse_screen)
              cnt = context.main_menu_component.browse_screen.filtered_count
              [(cnt || 0) - 1, 0].max
            else
              epubs = context.instance_variable_defined?(:@filtered_epubs) ? context.instance_variable_get(:@filtered_epubs) : []
              [(epubs&.length || 0) - 1, 0].max
            end
          end
          current = state.get(%i[menu browse_selected]) || 0
          new_val = [[current + delta, 0].max, max_idx].min
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: new_val))
          new_val
        end

        def recent_nav(context, delta)
          state = context.state
          items = begin
            EbookReader::RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          rescue StandardError
            []
          end
          max_idx = [items.length - 1, 0].max
          current = state.get(%i[menu browse_selected]) || 0
          new_val = [[current + delta, 0].max, max_idx].min
          state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: new_val))
          new_val
        end
      end
    end
  end
end
