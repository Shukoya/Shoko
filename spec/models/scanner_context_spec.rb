# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Models::ScannerContext do
  let(:epubs) { [] }
  let(:visited) { Set.new }
  subject(:context) { described_class.new(epubs: epubs, visited_paths: visited, depth: 0) }

  it 'allows construction with defaults' do
    minimal = described_class.new
    expect(minimal.depth).to be_nil
  end

  describe '#can_scan?' do
    it 'returns true when within limits and not visited' do
      expect(context.can_scan?('/books', 1, 1)).to be(true)
    end

    it 'returns false when depth exceeds max' do
      expect(context.can_scan?('/books', -1, 1)).to be(false)
    end

    it 'returns false when file limit reached' do
      epubs << 'a.epub'
      expect(context.can_scan?('/books', 1, 1)).to be(false)
    end

    it 'returns false when directory already visited' do
      visited.add('/books')
      expect(context.can_scan?('/books', 1, 2)).to be(false)
    end
  end

  describe '#mark_visited' do
    it 'adds directory to visited_paths' do
      context.mark_visited('/tmp')
      expect(visited).to include('/tmp')
    end
  end

  describe '#with_deeper_depth' do
    it 'returns new context with incremented depth' do
      deeper = context.with_deeper_depth
      expect(deeper.depth).to eq(1)
      expect(deeper.epubs).to equal(epubs)
      expect(deeper.visited_paths).to equal(visited)
    end
  end

  describe 'serialization' do
    it 'round-trips via to_h' do
      expect(described_class.new(**context.to_h)).to eq(context)
    end
  end
end
