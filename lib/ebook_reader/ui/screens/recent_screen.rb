# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative '../../components/surface'
require_relative '../../components/rect'
require 'time'

module EbookReader
  module UI
    module Screens
      # Screen that lists recently opened books and allows
      # quick navigation back to them.
      class RecentScreen
        include EbookReader::Constants

        attr_accessor :selected

        RenderContext = Struct.new(:recent_files, :params, :height, :width)
        private_constant :RenderContext

        def initialize(menu, _renderer = nil)
          @menu = menu
          @selected = 0
          @renderer = nil
        end

        def draw(height, width)
          surface = EbookReader::Components::Surface.new(Terminal)
          bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          items = load_recent_books

          # Header
          surface.write(bounds, 1, 2, "#{UIConstants::COLOR_TEXT_ACCENT}🕒 Recent Books#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, [width - 20, 60].max,
                        "#{UIConstants::COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}")

          if items.empty?
            surface.write(bounds, height / 2, [(width - 20) / 2, 1].max,
                          "#{UIConstants::COLOR_TEXT_DIM}No recent books#{Terminal::ANSI::RESET}")
          else
            list_start = 4
            max_items = [(height - 6) / 2, 10].min
            items.take(max_items).each_with_index do |book, i|
              row_base = list_start + (i * 2)
              next if row_base >= height - 2

              render_recent_item(surface, bounds, row_base, width, book, i)
            end
          end

          surface.write(bounds, height - 1, 2,
                        "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}")
        end

        private

        def renderer = nil

        def load_recent_books
          recent = RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          @selected = 0 if @selected >= recent.length
          recent
        end

        def render_recent_item(surface, bounds, row, width, book, index)
          if index == @selected
            surface.write(bounds, row, 2,
                          UIConstants::SELECTION_POINTER_COLOR + UIConstants::SELECTION_POINTER + Terminal::ANSI::RESET)
            surface.write(bounds, row, 4,
                          UIConstants::SELECTION_HIGHLIGHT + (book['name'] || 'Unknown') + Terminal::ANSI::RESET)
          else
            surface.write(bounds, row, 2, '  ')
            surface.write(bounds, row, 4,
                          UIConstants::COLOR_TEXT_PRIMARY + (book['name'] || 'Unknown') + Terminal::ANSI::RESET)
          end
          if book['accessed']
            time_ago = @menu.send(:time_ago_in_words, Time.parse(book['accessed']))
            surface.write(bounds, row, [width - 20, 60].max,
                          UIConstants::COLOR_TEXT_DIM + time_ago + Terminal::ANSI::RESET)
          end
          return unless row + 1 < bounds.height - 2

          path = (book['path'] || '').sub(Dir.home, '~')
          surface.write(bounds, row + 1, 6,
                        UIConstants::COLOR_TEXT_DIM + path[0, width - 8] + Terminal::ANSI::RESET)
        end

        # Rendering delegated to MainMenuRenderer
      end
    end
  end
end
