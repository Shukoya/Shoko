# frozen_string_literal: true

require_relative '../terminal'

module EbookReader
  module Constants
    # Centralized UI color and style definitions
    module UIConstants
      # Dimensions
      MIN_WIDTH = 60
      MIN_HEIGHT = 20

      # Base Colors
      COLOR_TEXT_PRIMARY = Terminal::ANSI::WHITE
      COLOR_TEXT_SECONDARY = Terminal::ANSI::GRAY
      COLOR_TEXT_DIM = Terminal::ANSI::DIM
      COLOR_TEXT_ACCENT = Terminal::ANSI::BRIGHT_CYAN
      COLOR_TEXT_SUCCESS = Terminal::ANSI::GREEN
      COLOR_TEXT_WARNING = Terminal::ANSI::YELLOW
      COLOR_TEXT_ERROR = Terminal::ANSI::RED

      # Backgrounds
      BG_PRIMARY = Terminal::ANSI::BG_DARK
      BG_ACCENT = Terminal::ANSI::BG_BRIGHT_YELLOW

      # Borders & Dividers
      BORDER_PRIMARY = Terminal::ANSI::GRAY
      BORDER_ACCENT = Terminal::ANSI::BRIGHT_CYAN

      # Selections & Highlights
      SELECTION_POINTER = '▸ '
      SELECTION_FG = Terminal::ANSI::BLACK
      SELECTION_POINTER_COLOR = Terminal::ANSI::BRIGHT_GREEN
      SELECTION_HIGHLIGHT = Terminal::ANSI::BRIGHT_WHITE

      # Overlay/Highlight backgrounds
      HIGHLIGHT_BG_ACTIVE = Terminal::ANSI::BG_BLUE
      HIGHLIGHT_BG_SAVED = Terminal::ANSI::BG_CYAN

      # Popup menu colors
      POPUP_BG_DEFAULT = BG_PRIMARY
      POPUP_BG_SELECTED = BG_ACCENT
      POPUP_FG_DEFAULT = COLOR_TEXT_PRIMARY
      POPUP_FG_SELECTED = SELECTION_FG

      # Icons
      ICON_BOOK = '󰂺'
      ICON_RECENT = '󰁯'
      ICON_ANNOTATION = '󰠮'
      ICON_SETTINGS = ''
      ICON_QUIT = '󰿅'
      ICON_OPEN = '󰷏'
      ICON_TOC = '📖'
      ICON_BOOKMARK = '🔖'
      ICON_HELP = '❓'
      ICON_SEARCH = ''
      ICON_REFRESH = ''
    end
  end
end
