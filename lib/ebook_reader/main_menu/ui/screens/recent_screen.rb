# frozen_string_literal: true

require_relative '../recent_item_renderer'

module EbookReader
  module UI
    module Screens
      # A screen to display recently opened files.
      class RecentScreen
        attr_accessor :selected

        def initialize(main_menu, renderer)
          @main_menu = main_menu
          @renderer = renderer
          @selected = 0
          @recent_books = []
        end

        def draw
          @recent_books = load_recent_books
          @renderer.clear_screen
          @renderer.draw_box
          @renderer.draw_text(1, 2, 'Recent Files', @renderer.header_color)
          draw_recent_list
        end

        def load_recent_books
          RecentFiles.list.map do |path, time|
            { 'path' => path, 'time' => time }
          end
        end

        def draw_recent_list
          return if @recent_books.nil?

          @recent_books.each_with_index do |book, i|
            is_selected = (i == @selected)
            UI::RecentItemRenderer.new(book, i, is_selected, @renderer).render
          end
        end
      end
    end
  end
end