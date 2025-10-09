# frozen_string_literal: true

require_relative 'base_service'
require_relative '../../models/selection_anchor'

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
          normalized = coordinate_service.normalize_selection_range(selection_range, rendered_lines)
          return '' unless normalized

          start_anchor = EbookReader::Models::SelectionAnchor.from(normalized[:start])
          end_anchor = EbookReader::Models::SelectionAnchor.from(normalized[:end])
          return '' unless start_anchor && end_anchor

          geometry_index = build_geometry_index(rendered_lines)
          return '' if geometry_index.empty?

          ordered = order_geometry(geometry_index.values)
          start_idx = ordered.find_index { |geo| geo.key == start_anchor.geometry_key }
          end_idx = ordered.find_index { |geo| geo.key == end_anchor.geometry_key }
          return '' unless start_idx && end_idx

          text_lines = []

          ordered[start_idx..end_idx].each do |geometry|
            start_cell = geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
            end_cell = geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length

            next if end_cell < start_cell

            start_char = char_index_for_cell(geometry, start_cell)
            end_char = char_index_for_cell(geometry, end_cell)
            segment = geometry.plain_text[start_char...end_char]
            next if segment.nil?

            text_lines << segment
          end

          text_lines.join("\n")
        end

        protected

        def required_dependencies
          [:coordinate_service]
        end

        private

        def build_geometry_index(rendered_lines)
          rendered_lines.each_with_object({}) do |(_key, info), acc|
            geometry = info[:geometry]
            next unless geometry

            acc[geometry.key] = geometry
          end
        end

        def order_geometry(geometries)
          geometries.sort_by do |geo|
            [geo.page_id || 0, geo.line_offset || 0, geo.column_id || 0, geo.row || 0, geo.column_origin || 0]
          end
        end

        def char_index_for_cell(geometry, cell_index)
          cells = geometry.cells
          return 0 if cells.empty?

          if cell_index <= 0
            0
          elsif cell_index >= cells.length
            geometry.plain_text.length
          else
            cells[cell_index].char_start
          end
        end
      end
    end
  end
end
