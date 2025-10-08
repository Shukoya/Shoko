# frozen_string_literal: true

module EbookReader
  module Components
    module UI
      module BoxDrawer
        def draw_box(surface, bounds, y, x, h, w, label: nil)
          # Top border
          hline = '─' * (w - 2)
          surface.write(bounds, y, x, "╭#{hline}╮")
          surface.write(bounds, y, x + 2, "[ #{label} ]") if label && w > (label.to_s.length + 6)
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
