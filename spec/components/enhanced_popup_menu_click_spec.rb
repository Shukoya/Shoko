# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::EnhancedPopupMenu do
  class FakeCoord
    def calculate_popup_position(_end_pos, _width, _height)
      { x: 10, y: 5 }
    end

    def within_bounds?(col, row, rect)
      col >= rect.x && col < (rect.x + rect.width) && row >= rect.y && row < (rect.y + rect.height)
    end

    def normalize_selection_range(selection_range, _rendered_lines = nil) = selection_range
  end

  class FakeClipboard
    def available? = false
  end

  let(:geometry) do
    cell_data = EbookReader::Helpers::TextMetrics.cell_data_for('popup range')
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
      row: 3,
      column_origin: 10,
      line_offset: 0,
      plain_text: 'popup range',
      styled_text: 'popup range',
      cells: cells
    )
  end

  let(:rendered_lines) do
    {
      geometry.key => {
        row: geometry.row,
        col: geometry.column_origin,
        col_end: geometry.column_origin + geometry.visible_width,
        width: geometry.visible_width,
        text: geometry.plain_text,
        geometry: geometry,
      },
    }
  end

  let(:selection) do
    start_anchor = EbookReader::Models::SelectionAnchor.new(
      page_id: geometry.page_id,
      column_id: geometry.column_id,
      geometry_key: geometry.key,
      line_offset: geometry.line_offset,
      cell_index: 0,
      row: geometry.row,
      column_origin: geometry.column_origin
    )
    end_anchor = start_anchor.with_cell_index(3)
    { start: start_anchor.to_h, end: end_anchor.to_h }
  end

  it 'handles click to select and returns action' do
    menu = described_class.new(selection, nil, FakeCoord.new, FakeClipboard.new, rendered_lines)
    # Click first item row at computed y
    result = menu.handle_click(10, 5) # x,y
    expect(result).to be_a(Hash)
    expect(result[:type]).to eq(:action)
    expect(result[:action]).to eq(:create_annotation)
  end

  it 'handles cancel key' do
    menu = described_class.new(selection, nil, FakeCoord.new, FakeClipboard.new, rendered_lines)
    res = menu.handle_key("\e")
    expect(res[:type]).to eq(:cancel)
  end
end
