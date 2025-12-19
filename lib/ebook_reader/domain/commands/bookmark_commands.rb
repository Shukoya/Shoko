# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Bookmark management commands using domain services.
      class BookmarkCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "bookmark_#{action}",
            description: description || "Bookmark #{action.to_s.tr('_', ' ')}"
          )
        end

        def can_execute?(context, _params = {})
          deps = context.dependencies
          deps.registered?(:bookmark_service) && deps.registered?(:state_store)
        end

        protected

        def perform(context, params = {})
          deps = context.dependencies
          bookmark_service = deps.resolve(:bookmark_service)

          case @action
          when :add
            handle_add_bookmark(bookmark_service, params)
          when :remove
            handle_remove_bookmark(bookmark_service, params)
          when :toggle
            handle_toggle_bookmark(bookmark_service, params)
          when :jump_to
            handle_jump_to_bookmark(bookmark_service, params)
          else
            raise ExecutionError.new("Unknown bookmark action: #{@action}", command_name: name)
          end

          @action
        end

        private

        def handle_add_bookmark(service, params)
          text_snippet = params[:text_snippet]
          service.add_bookmark(text_snippet)
        end

        def handle_remove_bookmark(service, params)
          bookmark = params[:bookmark]

          raise ValidationError.new('Bookmark required for remove action', command_name: name) unless bookmark

          service.remove_bookmark(bookmark)
        end

        def handle_toggle_bookmark(service, params)
          text_snippet = params[:text_snippet]
          result = service.toggle_bookmark(text_snippet)

          { result: result }
        end

        def handle_jump_to_bookmark(service, params)
          bookmark = params[:bookmark]

          raise ValidationError.new('Bookmark required for jump_to action', command_name: name) unless bookmark

          service.jump_to_bookmark(bookmark)
        end
      end

      # Command for navigating and mutating the in-reader bookmarks list.
      class BookmarkListCommand < BaseCommand
        def initialize(list_action, name: nil, description: nil)
          @list_action = list_action
          super(
            name: name || "bookmarks_#{list_action}",
            description: description || "Bookmarks list #{list_action.to_s.tr('_', ' ')}"
          )
        end

        protected

        def perform(context, _params = {})
          case @list_action
          when :navigate_up
            handle_navigate_list(context, :up)
          when :navigate_down
            handle_navigate_list(context, :down)
          when :select_current
            handle_select_current(context)
          when :delete_current
            handle_delete_current(context)
          else
            raise ExecutionError.new("Unknown bookmark list action: #{@list_action}",
                                     command_name: name)
          end
        end

        private

        def handle_navigate_list(context, direction)
          state_store = context.dependencies.resolve(:state_store)
          current_state = state_store.current_state

          bookmarks = current_state.dig(:reader, :bookmarks) || []
          return if bookmarks.empty?

          current_selection = current_state.dig(:reader, :bookmark_selected) || 0

          new_selection = case direction
                          when :up
                            [current_selection - 1, 0].max
                          when :down
                            [current_selection + 1, bookmarks.size - 1].min
                          else
                            current_selection
                          end

          state_store.set(%i[reader bookmark_selected], new_selection)
        end

        def handle_select_current(context)
          deps = context.dependencies
          state_store = deps.resolve(:state_store)
          current_state = state_store.current_state

          bookmarks = current_state.dig(:reader, :bookmarks) || []
          selected_index = current_state.dig(:reader, :bookmark_selected) || 0

          return unless selected_index < bookmarks.size

          bookmark = bookmarks[selected_index]
          bookmark_service = deps.resolve(:bookmark_service)
          bookmark_service.jump_to_bookmark(bookmark)

          # Switch back to reading mode
          state_store.set(%i[reader mode], :read)
        end

        def handle_delete_current(context)
          deps = context.dependencies
          state_store = deps.resolve(:state_store)
          current_state = state_store.current_state

          bookmarks = current_state.dig(:reader, :bookmarks) || []
          selected_index = current_state.dig(:reader, :bookmark_selected) || 0

          return unless selected_index < bookmarks.size

          bookmark = bookmarks[selected_index]
          bookmark_service = deps.resolve(:bookmark_service)
          bookmark_service.remove_bookmark(bookmark)

          # Adjust selection if needed
          new_bookmarks = bookmark_service.bookmarks
          nb_size = new_bookmarks.size
          return unless selected_index >= nb_size && nb_size.positive?

          state_store.set(%i[reader bookmark_selected], nb_size - 1)
        end
      end

      # Factory methods for bookmark commands
      module BookmarkCommandFactory
        def self.add_bookmark(text_snippet = nil)
          command = BookmarkCommand.new(:add)

          # If text_snippet provided, create a wrapper that includes it in params
          if text_snippet
            lambda do |context, params = {}|
              command.execute(context, params.merge(text_snippet: text_snippet))
            end
          else
            command
          end
        end

        def self.remove_bookmark(bookmark)
          command = BookmarkCommand.new(:remove)
          lambda do |context, params = {}|
            command.execute(context, params.merge(bookmark: bookmark))
          end
        end

        def self.toggle_bookmark(text_snippet = nil)
          command = BookmarkCommand.new(:toggle)
          lambda do |context, params = {}|
            command.execute(context, params.merge(text_snippet: text_snippet))
          end
        end

        def self.jump_to_bookmark(bookmark)
          command = BookmarkCommand.new(:jump_to)
          lambda do |context, params = {}|
            command.execute(context, params.merge(bookmark: bookmark))
          end
        end

        # List navigation commands
        def self.navigate_bookmarks_up
          BookmarkListCommand.new(:navigate_up)
        end

        def self.navigate_bookmarks_down
          BookmarkListCommand.new(:navigate_down)
        end

        def self.select_current_bookmark
          BookmarkListCommand.new(:select_current)
        end

        def self.delete_current_bookmark
          BookmarkListCommand.new(:delete_current)
        end
      end
    end
  end
end
