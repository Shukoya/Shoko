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
          search_cursor = EbookReader::Domain::Selectors::MenuSelectors.search_cursor(@state)
          search_query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(search_cursor: (search_cursor + delta).clamp(
            0, search_query.length
          )))
        end

        def handle_delete
          search_cursor = EbookReader::Domain::Selectors::MenuSelectors.search_cursor(@state)
          search_query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state)
          return if search_cursor >= search_query.length

          query = search_query.dup
          query.slice!(search_cursor)
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(search_query: query))
          filter_books
        end

        def filter_books
          search_query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state)
          @filtered_epubs = if search_query.empty?
                              @scanner.epubs
                            else
                              filter_by_query
                            end
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(browse_selected: 0))
        end

        def filter_by_query
          query = EbookReader::Domain::Selectors::MenuSelectors.search_query(@state).downcase
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
