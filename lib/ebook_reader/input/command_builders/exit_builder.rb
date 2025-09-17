# frozen_string_literal: true

require_relative 'helpers'

module EbookReader
  module Input
    module CommandBuilders
      class ExitBuilder
        include Helpers

        def initialize(action)
          @action = action
        end

        def build
          commands = {}
          KeyDefinitions::ACTIONS[:cancel].each { |key| commands[key] = @action }
          commands
        end
      end
    end
  end
end
