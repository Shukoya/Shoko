# frozen_string_literal: true

require_relative 'key_definitions'

module EbookReader
  module Input
    # Factory for creating common input command patterns
    # This eliminates the duplication of similar lambda patterns across the codebase
    class CommandFactory
      include KeyDefinitions::Helpers

      class << self
        # Navigation commands - used by TOC, bookmarks, menus, etc.
        def navigation_commands(_context, selection_field, max_value_proc)
          commands = {}

          # Resolve target field and action type for consistent state mutations
          field = selection_field.to_sym
          action_type = case field
                        when :selected, :browse_selected
                          :menu
                        when :toc_selected, :bookmark_selected
                          :selections
                        when :sidebar_toc_selected, :sidebar_bookmarks_selected, :sidebar_annotations_selected
                          :sidebar
                        end
          return commands unless action_type

          base_path = (action_type == :menu ? :menu : :reader)

          # Up/Down navigation
          ups = KeyDefinitions::NAVIGATION[:up]
          ups.each do |key|
            commands[key] = lambda do |ctx, _|
              current = value_at(ctx, base_path, field)
              new_val = [current - 1, 0].max
              dispatch_for(ctx, action_type, field, new_val)
              :handled
            end
          end

          downs = KeyDefinitions::NAVIGATION[:down]
          downs.each do |key|
            commands[key] = lambda do |ctx, _|
              current = value_at(ctx, base_path, field)
              max_val = max_value_proc.call(ctx)
              new_val = (current + 1).clamp(0, max_val)
              dispatch_for(ctx, action_type, field, new_val)
              :handled
            end
          end

          commands
        end

        # Exit commands - used by most modal screens
        def exit_commands(exit_action)
          commands = {}

          cancels = KeyDefinitions::ACTIONS[:cancel]
          cancels.each do |key|
            commands[key] = exit_action
          end

          commands
        end

        # Menu selection commands
        def menu_selection_commands
          commands = {}

          confirms = KeyDefinitions::ACTIONS[:confirm]
          confirms.each do |key|
            commands[key] = lambda do |ctx, _|
              ctx.handle_menu_selection
              :handled
            end
          end

          commands
        end

        # Reader navigation commands
        def reader_navigation_commands
          commands = {}
          reader = KeyDefinitions::READER

          # Page navigation
          map_keys!(commands, reader[:next_page], :next_page)
          map_keys!(commands, reader[:prev_page], :prev_page)
          map_keys!(commands, reader[:scroll_down], :scroll_down)
          map_keys!(commands, reader[:scroll_up], :scroll_up)

          # Chapter navigation
          map_keys!(commands, reader[:next_chapter], :next_chapter)
          map_keys!(commands, reader[:prev_chapter], :prev_chapter)

          # Position commands
          map_keys!(commands, reader[:go_to_start], :go_to_start)
          map_keys!(commands, reader[:go_to_end], :go_to_end)

          commands
        end

        # Reader control commands
        def reader_control_commands
          commands = {}
          reader = KeyDefinitions::READER
          actions = KeyDefinitions::ACTIONS

          map_keys!(commands, reader[:toggle_view], :toggle_view_mode)
          map_keys!(commands, reader[:toggle_page_mode], :toggle_page_numbering_mode)
          map_keys!(commands, reader[:increase_spacing], :increase_line_spacing)
          map_keys!(commands, reader[:decrease_spacing], :decrease_line_spacing)
          map_keys!(commands, reader[:show_toc], :open_toc)
          map_keys!(commands, reader[:add_bookmark], :add_bookmark)
          map_keys!(commands, reader[:show_bookmarks], :open_bookmarks)
          map_keys!(commands, reader[:show_help], :show_help)

          # Annotations list
          if reader.key?(:show_annotations)
            map_keys!(commands, reader[:show_annotations], :open_annotations)
          end

          # Pagination maintenance
          if reader.key?(:rebuild_pagination)
            map_keys!(commands, reader[:rebuild_pagination], :rebuild_pagination)
          end
          if reader.key?(:invalidate_pagination)
            map_keys!(commands, reader[:invalidate_pagination], :invalidate_pagination_cache)
          end

          map_keys!(commands, actions[:quit], :quit_to_menu)
          map_keys!(commands, actions[:force_quit], :quit_application)

          commands
        end

        # Text input commands (for search, file input)
        def text_input_commands(input_field, context_method = nil, cursor_field: nil)
          commands = {}

          # Map input fields to state paths
          input_paths = {
            search_query: %i[menu search_query],
            file_input: %i[menu file_input],
          }

          input_path = input_paths[input_field.to_sym]

          # Backspace
          backs = KeyDefinitions::ACTIONS[:backspace]
          has_cursor = !!cursor_field
          apply_value = lambda do |ctx, new_value, new_cursor = nil|
            if cursor_field && !new_cursor.nil?
              dispatch_menu(ctx, input_field => new_value, cursor_field => new_cursor)
            else
              dispatch_menu(ctx, input_field => new_value)
            end
          end
          determine_pos = lambda do |ctx, cur|
            cursor_field ? cursor_value(ctx, cursor_field, cur) : cur.length
          end

          backs.each do |key|
            commands[key] = lambda do |ctx, _|
              if context_method
                ctx.send(context_method, key)
              elsif input_path
                cur = current_value(ctx, input_path)
                pos = determine_pos.call(ctx, cur)
                new_value, new_cursor = splice_backspace(cur, pos)
                apply_value.call(ctx, new_value, new_cursor)
              end
              :handled
            end
          end

          # Character input (default handler)
          commands[:__default__] = lambda do |ctx, key|
            char = key.to_s
            if char.length == 1 && char.ord >= 32
              if context_method
                ctx.send(context_method, key)
              elsif input_path
                cur = current_value(ctx, input_path)
                pos = determine_pos.call(ctx, cur)
                new_value, new_cursor = splice_insert(cur, pos, char)
                apply_value.call(ctx, new_value, new_cursor)
              end
              :handled
            else
              :pass
            end
          end

          # Delete at cursor
          dels = KeyDefinitions::ACTIONS[:delete]
          dels.each do |key|
            commands[key] = lambda do |ctx, _|
              cur = current_value(ctx, input_path)
              pos = determine_pos.call(ctx, cur)
              new_value = splice_delete(cur, pos)
              apply_value.call(ctx, new_value)
              :handled
            end
          end

          commands
        end

        # Bookmark list commands
        def bookmark_commands(empty_handler = nil)
          commands = {}
          reader = KeyDefinitions::READER
          actions = KeyDefinitions::ACTIONS

          if empty_handler
            # For empty bookmark lists
            commands[:__default__] = lambda do |ctx, key|
              if reader[:show_bookmarks].include?(key) || actions[:cancel].include?(key)
                ctx.send(empty_handler)
                :handled
              else
                :pass
              end
            end
          else
            # For populated bookmark lists
            commands.merge!(navigation_commands(nil, :bookmark_selected, lambda { |ctx|
              (ctx.state.bookmarks || []).length - 1
            }))

            actions[:confirm].each do |key|
              commands[key] = :bookmark_select
            end

            commands['d'] = :delete_selected_bookmark

            exit_keys = Array(reader[:show_bookmarks]) + Array(actions[:cancel])
            exit_keys.each { |key| commands[key] = :exit_bookmarks }
          end

          commands
        end
      end

      class << self
        private

        def map_keys!(commands, keys, action)
          Array(keys).each { |key| commands[key] = action }
          commands
        end

        def value_at(ctx, base, field)
          (ctx.state.get([base, field]) || 0)
        end

        def dispatch_for(ctx, action_type, field, value)
          case action_type
          when :menu
            dispatch_menu(ctx, field => value)
          when :selections
            ctx.state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(field => value))
          when :sidebar
            ctx.state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(field => value))
          end
        end

        def dispatch_menu(ctx, hash)
          ctx.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(hash))
        end

        def current_value(ctx, input_path)
          (ctx.state.get(input_path) || '').to_s
        end

        def cursor_value(ctx, cursor_field, current)
          (ctx.state.get([:menu, cursor_field]) || current.length).to_i
        end

        def splice_backspace(current, cursor)
          return [current, cursor] unless cursor.positive?

          before = current[0, cursor - 1] || ''
          after = current[cursor..] || ''
          [before + after, cursor - 1]
        end

        def splice_insert(current, cursor, char)
          before = current[0, cursor] || ''
          after = current[cursor..] || ''
          [before + char + after, cursor + 1]
        end

        def splice_delete(current, cursor)
          return current unless cursor < current.length

          before = current[0, cursor] || ''
          after = current[(cursor + 1)..] || ''
          before + after
        end
      end
    end
  end
end
