# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Surface do
  let(:output) do
    Class.new do
      attr_reader :writes

      def initialize = @writes = []
      def write(r, c, t) = @writes << [r, c, t]
    end.new
  end
  let(:surface) { described_class.new(output) }
  let(:bounds) { EbookReader::Components::Rect.new(x: 5, y: 5, width: 10, height: 3) }

  it 'writes within bounds and clips text' do
    surface.write(bounds, 1, 1, 'abcdefghijk')
    expect(output.writes.first[0]).to eq(5)
    expect(output.writes.first[1]).to eq(5)
    expect(output.writes.first[2].length).to eq(10)
  end

  it 'fills a rectangle' do
    surface.fill(bounds, '.')
    # Should write once per row
    expect(output.writes.size).to eq(3)
  end
end
