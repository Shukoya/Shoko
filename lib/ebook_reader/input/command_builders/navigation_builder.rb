# frozen_string_literal: true

require_relative 'helpers'

module EbookReader
  module Input
    module CommandBuilders
      # Builds key bindings for up/down navigation of a selection field.
      class NavigationBuilder
        include Helpers

        def initialize(selection_field:, max_value_proc:)
          @selection_field = selection_field.to_sym
          @max_value_proc = max_value_proc
        end

        def build
          return {} unless action_type

          commands = {}
          register_navigation(commands, :up, -1)
          register_navigation(commands, :down, +1)
          commands
        end

        private

        attr_reader :selection_field, :max_value_proc

        def register_navigation(commands, direction, step)
          handler = navigation_handler(step)
          navigation_keys(direction).each { |key| commands[key] = handler }
        end

        def navigation_handler(step)
          lambda do |ctx, _|
            current = value_at(ctx, base_path, selection_field)
            target = if step.negative?
                       [current + step, 0].max
                     else
                       max_val = max_value_proc.call(ctx)
                       (current + step).clamp(0, max_val)
                     end
            dispatch_for(ctx, action_type, selection_field, target)
            :handled
          end
        end

        def action_type
          @action_type ||= case selection_field
                           when :selected, :browse_selected
                             :menu
                           when :sidebar_toc_selected, :sidebar_bookmarks_selected, :sidebar_annotations_selected
                             :sidebar
                           end
        end

        def base_path
          action_type == :menu ? :menu : :reader
        end
      end
    end
  end
end
