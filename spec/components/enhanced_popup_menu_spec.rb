# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::EnhancedPopupMenu do
  let(:coord) { EbookReader::Domain::Services::CoordinateService.new(EbookReader::Domain::ContainerFactory.create_test_container) }
  let(:clipboard) { double('Clipboard', available?: true) }

  def build_geometry(text, row:, col_origin:)
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
      line_offset: 0,
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

  def rendered_entry(geometry)
    {
      row: geometry.row,
      col: geometry.column_origin,
      col_end: geometry.column_origin + geometry.visible_width,
      width: geometry.visible_width,
      text: geometry.plain_text,
      geometry: geometry,
    }
  end

  it 'builds menu and navigates selection with keys' do
    geometry = build_geometry('menu selection', row: 5, col_origin: 4)
    rendered_lines = { geometry.key => rendered_entry(geometry) }
    range = {
      start: anchor_for(geometry, 0).to_h,
      end: anchor_for(geometry, 3).to_h,
    }
    allow(coord).to receive(:calculate_popup_position).and_return({ x: 1, y: 1 })
    menu = described_class.new(range, nil, coord, clipboard, rendered_lines)
    expect(menu.visible).to be true

    up = EbookReader::Input::KeyDefinitions::NAVIGATION[:up].first
    down = EbookReader::Input::KeyDefinitions::NAVIGATION[:down].first
    confirm = EbookReader::Input::KeyDefinitions::ACTIONS[:confirm].first

    menu.handle_key(down)
    menu.handle_key(up)
    result = menu.handle_key(confirm)
    expect(result).to be_a(Hash)
    expect(result[:type]).to eq(:action)
  end
end
