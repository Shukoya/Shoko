# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::WrappingService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  subject(:service) { described_class.new(container) }

  it 'wraps only the requested window' do
    lines = [
      'one two three four five six seven eight nine ten',
      'eleven twelve thirteen fourteen fifteen sixteen seventeen',
    ]
    # width 5 produces many short segments; request a window in the middle
    slice = service.wrap_window(lines, 0, 5, 3, 4)
    expect(slice).to be_a(Array)
    expect(slice.length).to eq(4)
  end

  it 'returns empty when start beyond wrapped size' do
    lines = ['short']
    slice = service.wrap_window(lines, 0, 80, 10, 5)
    expect(slice).to eq([])
  end
end
