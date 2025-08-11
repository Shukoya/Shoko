# frozen_string_literal: true

module EbookReader
  module Services
    # Centralized layout calculation service
    # Eliminates duplicate layout logic scattered across components
    class LayoutService
      def self.calculate_metrics(width, height, view_mode)
        col_width = if view_mode == :split
                      [(width - 3) / 2, 20].max
                    else
                      (width * 0.9).to_i.clamp(30, 120)
                    end
        content_height = [height - 2, 1].max
        [col_width, content_height]
      end

      def self.adjust_for_line_spacing(height, line_spacing)
        return 1 if height <= 0

        line_spacing == :relaxed ? [height / 2, 1].max : height
      end

      def self.calculate_center_start_row(content_height, lines_count, line_spacing)
        actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
        padding = [(content_height - actual_lines) / 2, 0].max
        [3 + padding, 3].max
      end
    end
  end
end