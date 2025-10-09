# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::TooltipOverlayComponent do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:coordinate_service) { EbookReader::Domain::Services::CoordinateService.new(container) }
  let(:state_store) { EbookReader::Infrastructure::StateStore.new }
  let(:controller) { double('Controller', state: state_store) }
  let(:component) { described_class.new(controller, coordinate_service: coordinate_service) }

  def build_geometry(text, row:, col_origin:, line_offset: 0, column_id: 0)
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

  it 'highlights full double-width graphemes without truncation' do
    geometry = build_geometry('漢漢', row: 6, col_origin: 2)
    rendered_lines = { geometry.key => rendered_line_entry(geometry) }
    state_store.set(%i[reader rendered_lines], rendered_lines)

    selection = {
      start: anchor_for(geometry, 0).to_h,
      end: anchor_for(geometry, geometry.cells.length).to_h,
    }
    state_store.set(%i[reader selection], selection)

    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 40, height: 20)

    EbookReader::TestSupport::TerminalDouble.reset!
    component.send(:render_active_selection, surface, bounds)

    highlight_write = EbookReader::TestSupport::TerminalDouble.writes.find do |entry|
      entry[:text].include?('漢') && entry[:text].include?(EbookReader::Components::TooltipOverlayComponent::HIGHLIGHT_BG_ACTIVE)
    end

    expect(highlight_write).not_to be_nil
    expect(highlight_write[:text]).to include('漢漢')
  end

  it 'highlights selections spanning split-view columns' do
    left = build_geometry('left column text', row: 4, col_origin: 3, line_offset: 0, column_id: 0)
    right = build_geometry('right column data', row: 4, col_origin: 33, line_offset: 10, column_id: 1)
    rendered_lines = {
      left.key => rendered_line_entry(left),
      right.key => rendered_line_entry(right),
    }
    state_store.set(%i[reader rendered_lines], rendered_lines)

    selection = {
      start: anchor_for(left, 0).to_h,
      end: anchor_for(right, 3).to_h,
    }
    state_store.set(%i[reader selection], selection)

    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 30)

    EbookReader::TestSupport::TerminalDouble.reset!
    component.send(:render_active_selection, surface, bounds)

    writes = EbookReader::TestSupport::TerminalDouble.writes.select do |entry|
      entry[:text].include?(EbookReader::Components::TooltipOverlayComponent::HIGHLIGHT_BG_ACTIVE)
    end

    expect(writes.length).to be >= 2
    left_write = writes.find { |entry| entry[:col] == left.column_origin }
    right_write = writes.find { |entry| entry[:col] == right.column_origin }
    expect(left_write).not_to be_nil
    expect(right_write).not_to be_nil
  end
end
