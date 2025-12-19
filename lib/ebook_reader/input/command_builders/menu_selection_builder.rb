# frozen_string_literal: true

require_relative 'helpers'

module EbookReader
  module Input
    module CommandBuilders
      # Builds key bindings for selecting a menu item via confirm keys.
      class MenuSelectionBuilder
        include Helpers

        def build
          commands = {}
          KeyDefinitions::ACTIONS[:confirm].each do |key|
            commands[key] = lambda do |ctx, _|
              ctx.handle_menu_selection
              :handled
            end
          end
          commands
        end
      end
    end
  end
end
