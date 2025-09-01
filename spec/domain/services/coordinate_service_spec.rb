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
end

