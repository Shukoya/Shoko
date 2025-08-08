# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Handles browse screen rendering
      class BrowseScreen

        BROWSE_FOOTER_HINTS = '↑↓ Navigate • Enter Open • / Search • r Refresh • ESC Back'

        attr_accessor :selected, :search_query, :search_cursor, :filtered_epubs

        def initialize(scanner, renderer = nil)
          @scanner = scanner
          @selected = 0
          @search_query = ''
          @search_cursor = 0
          @filtered_epubs = []
          @renderer = renderer
        end

        def draw(height, width)
          @filtered_epubs ||= []
          renderer.render_browse_screen(
            UI::MainMenuRenderer::BrowseContext.new(
              height: height,
              width: width,
              selected: @selected,
              search_query: @search_query,
              search_cursor: @search_cursor,
              filtered_epubs: @filtered_epubs,
              scan_status: @scanner.scan_status,
              scan_message: @scanner.scan_message
            )
          )
        end

        private
        def renderer
          @renderer ||= UI::MainMenuRenderer.new(@menu_config || EbookReader::Config.new)
        end

        def calculate_visible_range(list_height)
          visible_start = [@selected - (list_height / 2), 0].max
          visible_end = [visible_start + list_height, @filtered_epubs.length].min

          if visible_end == @filtered_epubs.length && @filtered_epubs.length > list_height
            visible_start = [visible_end - list_height, 0].max
          end

          visible_start...visible_end
        end

        # Rendering logic handled by MainMenuRenderer
      end
    end
  end
end
