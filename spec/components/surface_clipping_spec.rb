# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Surface do
  class Capture
    attr_reader :calls

    def initialize = (@calls = [])

    def write(row, col, text)
      @calls << [row, col, text]
    end
  end

  it 'clips writes to bounds width and respects offsets' do
    cap = Capture.new
    surface = described_class.new(cap)
    bounds = EbookReader::Components::Rect.new(x: 5, y: 3, width: 10, height: 2)

    surface.write(bounds, 1, 1, '0123456789ABCDEFGHIJ')
    # Only one write, clipped to width 10 starting at absolute col 5
    expect(cap.calls.length).to eq(1)
    row, col, text = cap.calls.first
    expect(row).to eq(3)      # y + (row-1)
    expect(col).to eq(5)      # x + (col-1)
    expect(text.length).to eq(10)
    expect(text).to start_with('0123456789')
  end
end
