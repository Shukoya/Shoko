# frozen_string_literal: true

require_relative 'helpers'

module EbookReader
  module Input
    module CommandBuilders
      # Builds key bindings for reader navigation actions (pages, chapters, scrolling).
      class ReaderNavigationBuilder
        include Helpers

        def build
          commands = {}
          reader = KeyDefinitions::READER

          map_keys!(commands, reader[:next_page], :next_page)
          map_keys!(commands, reader[:prev_page], :prev_page)
          map_keys!(commands, reader[:scroll_down], :scroll_down)
          map_keys!(commands, reader[:scroll_up], :scroll_up)
          map_keys!(commands, reader[:next_chapter], :next_chapter)
          map_keys!(commands, reader[:prev_chapter], :prev_chapter)
          map_keys!(commands, reader[:go_to_start], :go_to_start)
          map_keys!(commands, reader[:go_to_end], :go_to_end)
          commands
        end
      end
    end
  end
end
