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

          # Map selection fields to state paths
          field_paths = {
            selected: [:menu, :selected],
            browse_selected: [:menu, :browse_selected],
            toc_selected: [:reader, :toc_selected],
            bookmark_selected: [:reader, :bookmark_selected],
            sidebar_toc_selected: [:reader, :sidebar_toc_selected],
            sidebar_bookmarks_selected: [:reader, :sidebar_bookmarks_selected],
            sidebar_annotations_selected: [:reader, :sidebar_annotations_selected]
          }

          field_path = field_paths[selection_field.to_sym]
          return commands unless field_path

          # Up navigation
          KeyDefinitions::NAVIGATION[:up].each do |key|
            commands[key] = lambda do |ctx, _|
              current = ctx.state.get(field_path)
              ctx.state.update(field_path, [current - 1, 0].max)
              :handled
            end
          end

          # Down navigation
          KeyDefinitions::NAVIGATION[:down].each do |key|
            commands[key] = lambda do |ctx, _|
              current = ctx.state.get(field_path)
              max_val = max_value_proc.call(ctx)
              ctx.state.update(field_path, [current + 1, max_val].min)
              :handled
            end
          end

          commands
        end

        # Exit commands - used by most modal screens
        def exit_commands(exit_action)
          commands = {}

          KeyDefinitions::ACTIONS[:cancel].each do |key|
            commands[key] = exit_action
          end

          commands
        end

        # Menu selection commands
        def menu_selection_commands
          commands = {}

          KeyDefinitions::ACTIONS[:confirm].each do |key|
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

          # Page navigation
          KeyDefinitions::READER[:next_page].each do |key|
            commands[key] = :next_page
          end

          KeyDefinitions::READER[:prev_page].each do |key|
            commands[key] = :prev_page
          end

          KeyDefinitions::READER[:scroll_down].each do |key|
            commands[key] = :scroll_down
          end

          KeyDefinitions::READER[:scroll_up].each do |key|
            commands[key] = :scroll_up
          end

          # Chapter navigation
          KeyDefinitions::READER[:next_chapter].each do |key|
            commands[key] = :next_chapter
          end

          KeyDefinitions::READER[:prev_chapter].each do |key|
            commands[key] = :prev_chapter
          end

          # Position commands
          KeyDefinitions::READER[:go_to_start].each do |key|
            commands[key] = :go_to_start
          end

          KeyDefinitions::READER[:go_to_end].each do |key|
            commands[key] = :go_to_end
          end

          commands
        end

        # Reader control commands
        def reader_control_commands
          commands = {}

          KeyDefinitions::READER[:toggle_view].each do |key|
            commands[key] = :toggle_view_mode
          end

          KeyDefinitions::READER[:toggle_page_mode].each do |key|
            commands[key] = :toggle_page_numbering_mode
          end

          KeyDefinitions::READER[:increase_spacing].each do |key|
            commands[key] = :increase_line_spacing
          end

          KeyDefinitions::READER[:decrease_spacing].each do |key|
            commands[key] = :decrease_line_spacing
          end

          KeyDefinitions::READER[:show_toc].each do |key|
            commands[key] = :open_toc
          end

          KeyDefinitions::READER[:add_bookmark].each do |key|
            commands[key] = :add_bookmark
          end

          KeyDefinitions::READER[:show_bookmarks].each do |key|
            commands[key] = :open_bookmarks
          end

          KeyDefinitions::READER[:show_help].each do |key|
            commands[key] = :show_help
          end

          # Annotations list
          if KeyDefinitions::READER.key?(:show_annotations)
            KeyDefinitions::READER[:show_annotations].each do |key|
              commands[key] = :open_annotations
            end
          end

          KeyDefinitions::ACTIONS[:quit].each do |key|
            commands[key] = :quit_to_menu
          end

          KeyDefinitions::ACTIONS[:force_quit].each do |key|
            commands[key] = :quit_application
          end

          commands
        end

        # Text input commands (for search, file input)
        def text_input_commands(input_field, context_method = nil)
          commands = {}

          # Map input fields to state paths
          input_paths = {
            search_query: [:menu, :search_query],
            file_input: [:menu, :file_input]
          }

          input_path = input_paths[input_field.to_sym]

          # Backspace
          KeyDefinitions::ACTIONS[:backspace].each do |key|
            commands[key] = lambda do |ctx, _|
              if context_method
                ctx.send(context_method, key)
              elsif input_path
                current = ctx.state.get(input_path)
                ctx.state.update(input_path, current.length.positive? ? current[0...-1] : current)
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
                current = ctx.state.get(input_path)
                ctx.state.update(input_path, current + char)
              end
              :handled
            else
              :pass
            end
          end

          commands
        end

        # Bookmark list commands
        def bookmark_commands(empty_handler = nil)
          commands = {}

          if empty_handler
            # For empty bookmark lists
            commands[:__default__] = lambda do |ctx, key|
              if KeyDefinitions::READER[:show_bookmarks].include?(key) ||
                 KeyDefinitions::ACTIONS[:cancel].include?(key)
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

            KeyDefinitions::ACTIONS[:confirm].each do |key|
              commands[key] = :bookmark_select
            end

            commands['d'] = :delete_selected_bookmark

            KeyDefinitions::READER[:show_bookmarks].each do |key|
              commands[key] = :exit_bookmarks
            end

            KeyDefinitions::ACTIONS[:cancel].each do |key|
              commands[key] = :exit_bookmarks
            end
          end

          commands
        end
      end
    end
  end
end
