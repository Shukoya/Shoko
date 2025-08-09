# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle search-related actions in the main menu.
      module SearchActions
        def handle_backspace
          @input_handler.send(:handle_backspace)
        end

        def searchable_key?(key)
          @input_handler.searchable_key?(key)
        end

        def add_to_search(key)
          @input_handler.send(:add_to_search, key)
        end

        def move_search_cursor(delta)
          @state.search_cursor = (@state.search_cursor + delta).clamp(0, @state.search_query.length)
        end

        def handle_delete
          return if @state.search_cursor >= @state.search_query.length

          query = @state.search_query.dup
          query.slice!(@state.search_cursor)
          @state.search_query = query
          filter_books
        end

        def filter_books
          @filtered_epubs = if @state.search_query.empty?
                              @scanner.epubs
                            else
                              filter_by_query
                            end
          @state.browse_selected = 0
        end

        def filter_by_query
          query = @state.search_query.downcase
          @scanner.epubs.select do |book|
            name = book['name'] || ''
            path = book['path'] || ''
            name.downcase.include?(query) || path.downcase.include?(query)
          end
        end
      end
    end
  end
end
