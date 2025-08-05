# frozen_string_literal: true

require_relative 'base_mode'

module EbookReader
  module ReaderModes
    # Displays help information
    class HelpMode < BaseMode
      HELP_CONTENT = [
        '',
        'Navigation Keys:',
        '  j / ↓     Scroll down',
        '  k / ↑     Scroll up',
        '  l / →     Next page',
        '  h / ←     Previous page',
        '  SPACE     Next page',
        '  n         Next chapter',
        '  p         Previous chapter',
        '  g         Go to beginning',
        '  G         Go to end',
        '',
        'View Options:',
        '  v         Toggle view mode',
        '  + / -     Adjust line spacing',
        '',
        'Features:',
        '  a         View annotations',
        '  A         View annotations',
        '  t         Table of Contents',
        '  b         Add bookmark',
        '  B         View bookmarks',
        '',
        'Other:',
        '  ?         Show/hide help',
        '  q         Quit to menu',
        '  Q         Quit application',
        '',
        'Press any key to continue...',
      ].freeze

      def draw(height, width)
        start_row = [(height - HELP_CONTENT.size) / 2, 1].max

        HELP_CONTENT.each_with_index do |line, idx|
          row = start_row + idx
          break if row >= height - 2

          col = [(width - line.length) / 2, 1].max
          terminal.write(row, col, Terminal::ANSI::WHITE + line + Terminal::ANSI::RESET)
        end
      end

      def handle_input(_key)
        reader.switch_mode(:read)
      end
    end
  end
end
