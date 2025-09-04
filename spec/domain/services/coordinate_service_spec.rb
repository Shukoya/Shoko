# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::CoordinateService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:service) { described_class.new(container) }

  describe '#normalize_selection_range' do
    it 'normalizes start/end positions and orders them' do
      range = { start: { x: 10, y: 5 }, end: { x: 2, y: 3 } }
      norm = service.normalize_selection_range(range)
      expect(norm[:start]).to eq({ x: 2, y: 3 })
      expect(norm[:end]).to eq({ x: 10, y: 5 })
    end
  end

  describe '#within_bounds?' do
    it 'returns true if point lies within rect' do
      rect = EbookReader::Components::Rect.new(x: 1, y: 1, width: 10, height: 5)
      expect(service.within_bounds?(5, 3, rect)).to be true
      expect(service.within_bounds?(12, 3, rect)).to be false
    end
  end

  describe '#calculate_popup_position' do
    it 'keeps popup within terminal bounds' do
      terminal = instance_double(EbookReader::Domain::Services::TerminalService)
      allow(container).to receive(:resolve).with(:terminal_service).and_return(terminal)
      allow(terminal).to receive(:size).and_return([20, 40])

      end_pos = { x: 38, y: 19 }
      pos = service.calculate_popup_position(end_pos, 10, 4)
      expect(pos[:x]).to be <= 40
      expect(pos[:y]).to be <= 20
    end
  end

  it 'normalizes positions and converts line coordinates' do
    pos = service.normalize_position({ 'x' => 1, 'y' => 2 })
    expect(pos).to eq({ x: 1, y: 2 })
    abs = service.line_to_terminal(5, 10, 3)
    expect(abs).to eq({ x: 15, y: 3 })
  end

  it 'detects column bounds and overlaps' do
    rendered = {
      'k' => { row: 5, col: 10, col_end: 20, text: 'abc', width: 11 },
    }
    bounds = service.column_bounds_for({ x: 12, y: 4 }, rendered)
    expect(bounds).to eq({ start: 10, end: 20 })
    expect(service.column_overlaps?(0, 5, bounds)).to be false
    expect(service.column_overlaps?(15, 25, bounds)).to be true
  end

  it 'validates coordinates and computes distance' do
    expect(service.validate_coordinates(5, 5, 10, 10)).to be true
    expect(service.validate_coordinates(0, 5, 10, 10)).to be false
    d = service.calculate_distance(0, 0, 3, 4)
    expect(d).to eq(5.0)
  end
end
