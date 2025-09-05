# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::EnhancedPopupMenu do
  class FakeCoord
    def calculate_popup_position(_end_pos, _w, _h)
      { x: 10, y: 5 }
    end
    def within_bounds?(x, y, rect)
      x >= rect.x && x < (rect.x + rect.width) && y >= rect.y && y < (rect.y + rect.height)
    end
    def normalize_selection_range(r) = r
  end

  class FakeClipboard
    def available? = false
  end

  let(:selection) do
    {
      start: { x: 1, y: 1 },
      end: { x: 5, y: 4 }
    }
  end

  it 'handles click to select and returns action' do
    menu = described_class.new(selection, nil, FakeCoord.new, FakeClipboard.new)
    # Click first item row at computed y
    result = menu.handle_click(10, 5) # x,y
    expect(result).to be_a(Hash)
    expect(result[:type]).to eq(:action)
    expect(result[:action]).to eq(:create_annotation)
  end

  it 'handles cancel key' do
    menu = described_class.new(selection, nil, FakeCoord.new, FakeClipboard.new)
    res = menu.handle_key("\e")
    expect(res[:type]).to eq(:cancel)
  end
end

