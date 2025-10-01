# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Domain service for layout calculations with dependency injection.
      # Migrated from legacy Services::LayoutService to follow DI pattern.
      class LayoutService < BaseService
        # Calculate layout metrics for given dimensions and view mode
        def calculate_metrics(width, height, view_mode)
          col_width = if view_mode == :split
                        [(width - 3) / 2, 20].max
                      else
                        (width * 0.9).to_i.clamp(30, 120)
                      end
          content_height = [height - 2, 1].max
          [col_width, content_height]
        end

        # Adjust height for line spacing
        def adjust_for_line_spacing(height, line_spacing)
          return 1 if height <= 0

          multiplier = resolve_multiplier(line_spacing)
          adjusted = (height * multiplier).floor
          adjusted = height if multiplier >= 1.0 && adjusted < height
          [adjusted, 1].max
        end

        # Calculate center start row for content
        def calculate_center_start_row(content_height, lines_count, line_spacing)
          actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
          padding = [(content_height - actual_lines) / 2, 0].max
          [3 + padding, 3].max
        end

        # Calculate optimal column width for text content
        def calculate_optimal_column_width(available_width, _content_length)
          # Use golden ratio for optimal reading width
          optimal = (available_width * 0.618).to_i
          optimal.clamp(40, 80) # Keep within readable bounds
        end

        # Calculate padding for centered content
        def calculate_centered_padding(container_width, content_width)
          [(container_width - content_width) / 2, 0].max
        end

        protected

        def required_dependencies
          [] # No dependencies required for layout calculations
        end

        private

        def resolve_multiplier(line_spacing)
          key = begin
                  line_spacing&.to_sym
                rescue StandardError
                  nil
                end
          EbookReader::Constants::LINE_SPACING_MULTIPLIERS.fetch(key, 1.0)
        end
      end
    end
  end
end
