# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::WrappingService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  subject(:service) { described_class.new(container) }

  it 'wraps lines with fallback when no cache present' do
    lines = [
      'This is a long line that should be wrapped properly',
      '',
      'short',
    ]
    wrapped = service.wrap_lines(lines, 0, 10)
    expect(wrapped).to be_an(Array)
    expect(wrapped.first.length).to be <= 10
  end

  it 'uses chapter cache when registered' do
    cache = double('ChapterCache')
    container.register(:chapter_cache, cache)
    expect(cache).to receive(:get_wrapped_lines).with(1, ['abc'], 10).and_return(['abc'])
    expect(service.wrap_lines(['abc'], 1, 10)).to eq(['abc'])
  end
end
