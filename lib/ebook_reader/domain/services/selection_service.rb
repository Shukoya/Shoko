# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Service to normalize selection ranges and extract text from rendered_lines
      # Centralizes logic used by UIController and MouseableReader
      class SelectionService < BaseService
        # Convenience helper: extract selection text directly from state.
        # If selection_range is nil, uses state[:reader][:selection].
        def extract_from_state(state, selection_range = nil)
          return '' unless state

          range = selection_range || state.get(%i[reader selection])
          rendered = state.get(%i[reader rendered_lines]) || {}
          extract_text(range, rendered)
        end

        # Extract selected text from selection_range using rendered_lines in state
        # @param selection_range [Hash] {:start=>{x:,y:}, :end=>{x:,y:}}
        # @param rendered_lines [Hash<Integer, Hash>] mapping of line_id => {row:, col:, col_end:, width:, text:}
        # @return [String]
        def extract_text(selection_range, rendered_lines)
          return '' unless selection_range && rendered_lines && !rendered_lines.empty?

          coordinate_service = resolve(:coordinate_service)
          normalized = coordinate_service.normalize_selection_range(selection_range)
          return '' unless normalized

          start_pos = normalized[:start]
          end_pos = normalized[:end]
          sy = start_pos[:y]
          ey = end_pos[:y]

          column_bounds = coordinate_service.column_bounds_for(start_pos, rendered_lines)
          return '' unless column_bounds

          text_lines = []

          (sy..ey).each do |y|
            terminal_row = y + 1

            parts = []
            rendered_lines.each_value do |line_info|
              next unless line_info[:row] == terminal_row

              line_start = line_info[:col]
              line_end = line_info[:col_end] || (line_start + line_info[:width] - 1)

              next unless coordinate_service.column_overlaps?(line_start, line_end, column_bounds)

              line_text = line_info[:text]
              row_start_x = y == sy ? start_pos[:x] : column_bounds[:start]
              row_end_x   = y == ey ? end_pos[:x]   : column_bounds[:end]

              next if row_end_x < line_start || row_start_x > line_end

              start_idx = [row_start_x - line_start, 0].max
              len = line_text.length
              end_idx   = [row_end_x - line_start, len - 1].min

              next unless end_idx >= start_idx && start_idx < len

              parts << { col: line_start, text: line_text[start_idx..end_idx] }
            end

            unless parts.empty?
              sorted = parts.sort_by { |p| p[:col] }
              text_lines << sorted.map { |p| p[:text] }.join(' ')
            end
          end

          text_lines.join("\n")
        end

        protected

        def required_dependencies
          [:coordinate_service]
        end
      end
    end
  end
end
