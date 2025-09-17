# frozen_string_literal: true

require_relative 'helpers'
require_relative 'navigation_builder'

module EbookReader
  module Input
    module CommandBuilders
      class BookmarkBuilder
        include Helpers

        def initialize(empty_handler = nil)
          @empty_handler = empty_handler
        end

        def build
          return empty_commands if empty_handler

          populated_commands
        end

        private

        attr_reader :empty_handler

        def empty_commands
          {
            :__default__ => lambda do |ctx, key|
              if trigger_keys.include?(key)
                ctx.send(empty_handler)
                :handled
              else
                :pass
              end
            end,
          }
        end

        def trigger_keys
          @trigger_keys ||= reader_keys(:show_bookmarks) + action_keys(:cancel)
        end

        def populated_commands
          commands = NavigationBuilder.new(selection_field: :bookmark_selected,
                                           max_value_proc: ->(ctx) { (ctx.state.bookmarks || []).length - 1 }).build

          action_keys(:confirm).each { |key| commands[key] = :bookmark_select }
          commands['d'] = :delete_selected_bookmark

          exit_keys = reader_keys(:show_bookmarks) + action_keys(:cancel)
          exit_keys.each { |key| commands[key] = :exit_bookmarks }
          commands
        end
      end
    end
  end
end
