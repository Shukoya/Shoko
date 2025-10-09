# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::SelectionService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:coordinate_service) { EbookReader::Domain::Services::CoordinateService.new(container) }
  let(:service) { described_class.new(container) }

  before do
    allow(container).to receive(:resolve).with(:coordinate_service).and_return(coordinate_service)
  end

  def build_geometry(text, row:, col_origin:, line_offset:, page_id: 0, column_id: 0)
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
      page_id: page_id,
      column_id: column_id,
      row: row,
      column_origin: col_origin,
      line_offset: line_offset,
      plain_text: text,
      styled_text: text,
      cells: cells
    )
  end

  def anchor_for(geometry, cell_index)
    EbookReader::Models::SelectionAnchor.new(
      page_id: geometry.page_id,
      column_id: geometry.column_id,
      geometry_key: geometry.key,
      line_offset: geometry.line_offset,
      cell_index: cell_index,
      row: geometry.row,
      column_origin: geometry.column_origin
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

  it 'extracts text across multiple geometries using anchors' do
    geom1 = build_geometry('hello world', row: 10, col_origin: 5, line_offset: 0)
    geom2 = build_geometry('selection ok', row: 11, col_origin: 5, line_offset: 1)
    rendered_lines = {
      geom1.key => rendered_line_entry(geom1),
      geom2.key => rendered_line_entry(geom2),
    }

    range = {
      start: anchor_for(geom1, 0).to_h,
      end: anchor_for(geom2, 5).to_h,
    }

    text = service.extract_text(range, rendered_lines)
    expect(text).to eq("hello world\nselec")
  end

  it 'handles selections defined via screen coordinates for compatibility' do
    geom = build_geometry('single line content', row: 5, col_origin: 1, line_offset: 0)
    rendered_lines = { geom.key => rendered_line_entry(geom) }

    range = { start: { x: 3, y: 4 }, end: { x: 15, y: 4 } }
    text = service.extract_text(range, rendered_lines)
    expect(text).to eq('gle line con')
  end

  it 'returns empty string for invalid data' do
    expect(service.extract_text(nil, {})).to eq('')
  end
end
