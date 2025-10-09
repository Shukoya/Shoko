# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::CoordinateService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:service) { described_class.new(container) }

  def build_geometry(text, row:, col_origin:, line_offset: 0)
    cell_data = EbookReader::Helpers::TextMetrics.cell_data_for(text)
    cells = cell_data.map do |cell|
      EbookReader::Models::LineCell.new(
        cluster: cell[:cluster],
        char_start: cell[:char_start],
        char_end: cell[:char_end],
        display_width: cell[:display_width],
        screen_x: cell[:screen_x]
      )
    end

    EbookReader::Models::LineGeometry.new(
      page_id: 0,
      column_id: 0,
      row: row,
      column_origin: col_origin,
      line_offset: line_offset,
      plain_text: text,
      styled_text: text,
      cells: cells
    )
  end

  def rendered_line_entry(geometry)
    {
      row: geometry.row,
      col: geometry.column_origin,
      col_end: geometry.column_origin + geometry.visible_width,
      width: geometry.visible_width,
      text: geometry.plain_text,
      geometry: geometry,
    }
  end

  it 'produces anchors for double-width graphemes' do
    geometry = build_geometry('漢字', row: 6, col_origin: 4)
    rendered_lines = { geometry.key => rendered_line_entry(geometry) }

    anchor = service.anchor_from_point({ x: 5, y: 5 }, rendered_lines, bias: :trailing)
    expect(anchor).to be_a(EbookReader::Models::SelectionAnchor)
    expect(anchor.cell_index).to eq(2)
  end

  it 'normalizes legacy coordinate ranges using rendered geometry' do
    geometry = build_geometry('example', row: 2, col_origin: 2)
    rendered = { geometry.key => rendered_line_entry(geometry) }

    range = { start: { x: 2, y: 1 }, end: { x: 5, y: 1 } }
    normalized = service.normalize_selection_range(range, rendered)

    expect(normalized[:start][:geometry_key]).to eq(geometry.key)
    expect(normalized[:end][:geometry_key]).to eq(geometry.key)
  end
end
