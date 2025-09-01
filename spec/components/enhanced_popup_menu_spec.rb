# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::EnhancedPopupMenu do
  let(:coord) { EbookReader::Domain::Services::CoordinateService.new(EbookReader::Domain::ContainerFactory.create_test_container) }
  let(:clipboard) { double('Clipboard', available?: true) }

  it 'builds menu and navigates selection with keys' do
    range = { start: { x: 1, y: 1 }, end: { x: 2, y: 1 } }
    allow(coord).to receive(:calculate_popup_position).and_return({ x: 1, y: 1 })
    menu = described_class.new(range, nil, coord, clipboard)
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
