# frozen_string_literal: true

require_relative 'helpers'

module EbookReader
  module Input
    module CommandBuilders
      # Builds key bindings for reader UI control actions (view mode, spacing, help, etc.).
      class ReaderControlBuilder
        include Helpers

        def build
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

          map_keys!(commands, reader[:show_annotations], :open_annotations) if reader.key?(:show_annotations)
          map_keys!(commands, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
          if reader.key?(:invalidate_pagination)
            map_keys!(commands, reader[:invalidate_pagination],
                      :invalidate_pagination_cache)
          end

          map_keys!(commands, actions[:quit], :quit_to_menu)
          map_keys!(commands, actions[:force_quit], :quit_application)
          commands
        end
      end
    end
  end
end
