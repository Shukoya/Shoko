# frozen_string_literal: true

require_relative '../../helpers/text_metrics'

module EbookReader
  module Components
    module UI
      module BoxDrawer
        def draw_box(surface, bounds, y, x, h, w, label: nil)
          # Top border
          hline = '─' * (w - 2)
          surface.write(bounds, y, x, "╭#{hline}╮")
          if label && w > 4
            label_text = "[ #{label} ]"
            available = w - 3
            clipped = EbookReader::Helpers::TextMetrics.truncate_to(label_text, available, start_column: x + 1)
            surface.write(bounds, y, x + 2, clipped) unless clipped.empty?
          end
          # Sides
          (1...(h - 1)).each do |i|
            row = y + i
            surface.write(bounds, row, x, '│')
            surface.write(bounds, row, x + w - 1, '│')
          end
          # Bottom
          surface.write(bounds, y + h - 1, x, "╰#{hline}╯")
        end
      end
    end
  end
end
