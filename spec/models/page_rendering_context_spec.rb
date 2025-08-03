# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Models::PageRenderingContext do
  subject(:context) do
    described_class.new(
      lines: [],
      offset: 0,
      dimensions: EbookReader::Models::Dimensions.new(width: 0, height: 0),
      position: EbookReader::Models::Position.new(row: 0, col: 0),
      show_page_num: true
    )
  end

  it 'allows construction with defaults' do
    minimal = described_class.new
    expect(minimal.lines).to be_nil
    expect(minimal.offset).to be_nil
  end

  it 'provides accessors' do
    expect(context.offset).to eq(0)
    context.offset = 2
    expect(context.offset).to eq(2)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**context.to_h)).to eq(context)
  end
end

RSpec.describe EbookReader::Models::FooterRenderingContext do
  subject(:context) do
    described_class.new(
      height: 0,
      width: 0,
      doc: double('Doc'),
      chapter: double('Chapter'),
      pages: [],
      view_mode: :single,
      mode: :read,
      line_spacing: 1,
      bookmarks: []
    )
  end

  it 'initializes with provided values' do
    expect(context.height).to eq(0)
    expect(context.view_mode).to eq(:single)
  end

  it 'allows mutation' do
    context.mode = :toc
    expect(context.mode).to eq(:toc)
  end

  it 'round-trips via to_h' do
    expect(described_class.new(**context.to_h)).to eq(context)
  end
end
