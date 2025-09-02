# frozen_string_literal: true

require_relative 'base_action'

module EbookReader
  module Domain
    module Actions
      # Switch reader mode: :read, :help, :toc, :bookmarks, :annotations
      class SwitchReaderModeAction < BaseAction
        VALID = %i[read help toc bookmarks annotations].freeze

        def apply(state)
          mode = (payload[:mode] || :read).to_sym
          return state.get(%i[reader mode]) unless VALID.include?(mode)

          state.update({ %i[reader mode] => mode })
          mode
        end
      end
    end
  end
end
