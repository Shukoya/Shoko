# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Models::DrawingContext do
  subject(:context) { described_class.new(row: 1, col: 2, width: 10, height: 5) }

  describe 'construction' do
    it 'allows missing keywords defaulting to nil' do
      minimal = described_class.new
      expect(minimal.row).to be_nil
      expect(minimal.col).to be_nil
    end

    it 'stores provided values' do
      expect(context.row).to eq(1)
      expect(context.col).to eq(2)
      expect(context.width).to eq(10)
      expect(context.height).to eq(5)
    end
  end

  describe 'mutators' do
    it 'allow attribute updates' do
      context.row = 9
      expect(context.row).to eq(9)
    end
  end

  describe '#position' do
    it 'returns a Position with matching coordinates' do
      expect(context.position).to eq(EbookReader::Models::Position.new(row: 1, col: 2))
    end
  end

  describe '#dimensions' do
    it 'returns a Dimensions with matching size' do
      expect(context.dimensions).to eq(EbookReader::Models::Dimensions.new(width: 10, height: 5))
    end
  end

  describe 'serialization' do
    it 'round-trips via to_h' do
      copy = described_class.new(**context.to_h)
      expect(copy).to eq(context)
    end
  end
end

RSpec.describe EbookReader::Models::BookmarkDrawingContext do
  let(:bookmark) { double('Bookmark') }
  let(:position) { EbookReader::Models::Position.new(row: 0, col: 0) }
  subject(:context) do
    described_class.new(bookmark: bookmark, chapter_title: 'Intro', index: 1, position: position, width: 0)
  end

  it 'allows construction with missing keywords' do
    empty = described_class.new
    expect(empty.bookmark).to be_nil
  end

  it 'provides attribute readers and writers' do
    expect(context.index).to eq(1)
    context.width = 12
    expect(context.width).to eq(12)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**context.to_h)).to eq(context)
  end
end

RSpec.describe EbookReader::Models::TocDrawingContext do
  let(:chapter) { double('Chapter') }
  let(:position) { EbookReader::Models::Position.new(row: 5, col: 3) }
  subject(:context) do
    described_class.new(chapter: chapter, index: 2, position: position, width: 20)
  end

  it 'stores values and allows mutation' do
    expect(context.index).to eq(2)
    context.index = 3
    expect(context.index).to eq(3)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**context.to_h)).to eq(context)
  end
end

RSpec.describe EbookReader::Models::LineDrawingContext do
  let(:position) { EbookReader::Models::Position.new(row: 0, col: 0) }
  subject(:context) do
    described_class.new(line: '', position: position, width: 0, line_count: 0)
  end

  it 'initializes with provided attributes' do
    expect(context.width).to eq(0)
    expect(context.line_count).to eq(0)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**context.to_h)).to eq(context)
  end
end

RSpec.describe EbookReader::Models::Position do
  subject(:pos) { described_class.new(row: -1, col: 0) }

  it 'allows attribute access and mutation' do
    expect(pos.row).to eq(-1)
    pos.col = 5
    expect(pos.col).to eq(5)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**pos.to_h)).to eq(pos)
  end
end

RSpec.describe EbookReader::Models::Dimensions do
  subject(:dims) { described_class.new(width: 0, height: 7) }

  it 'exposes attributes' do
    expect(dims.width).to eq(0)
    expect(dims.height).to eq(7)
  end

  it 'supports mutation' do
    dims.height = 9
    expect(dims.height).to eq(9)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**dims.to_h)).to eq(dims)
  end
end
