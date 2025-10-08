# frozen_string_literal: true

require_relative '../key_definitions'

module EbookReader
  module Input
    module CommandBuilders
      # Shared helpers for command builders to keep CommandFactory lean and
      # avoid repeated domain action construction.
      module Helpers
        include KeyDefinitions::Helpers

        NAVIGATION_CACHE = Hash.new do |cache, direction|
          cache[direction] = Array(KeyDefinitions::NAVIGATION[direction]).freeze
        end

        ACTION_CACHE = Hash.new do |cache, action|
          cache[action] = Array(KeyDefinitions::ACTIONS[action]).freeze
        end

        READER_CACHE = Hash.new do |cache, action|
          cache[action] = Array(KeyDefinitions::READER[action]).freeze
        end

        private

        def map_keys!(commands, keys, action)
          Array(keys).each { |key| commands[key] = action }
          commands
        end

        def navigation_keys(direction)
          NAVIGATION_CACHE[direction]
        end

        def action_keys(action)
          ACTION_CACHE[action]
        end

        def reader_keys(action)
          READER_CACHE[action]
        end

        def value_at(ctx, base, field)
          ctx.state.get([base, field]) || 0
        end

        def dispatch_for(ctx, action_type, field, value)
          case action_type
          when :menu
            dispatch_menu_field(ctx, field, value)
          when :selections
            dispatch_selection_field(ctx, field, value)
          when :sidebar
            dispatch_sidebar_field(ctx, field, value)
          end
        end

        def dispatch_menu_field(ctx, field, value)
          dispatch_menu(ctx, field => value)
        end

        def dispatch_selection_field(ctx, field, value)
          ctx.state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(field => value))
        end

        def dispatch_sidebar_field(ctx, field, value)
          ctx.state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(field => value))
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
