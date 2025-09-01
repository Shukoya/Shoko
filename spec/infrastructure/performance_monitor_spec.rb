# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::PerformanceMonitor do
  before { described_class.clear }

  it 'tracks durations for labels and reports stats' do
    3.times do
      described_class.time('op') { 1 + 1 }
    end
    stats = described_class.stats('op')
    expect(stats[:count]).to eq(3)
    expect(stats[:total]).to be > 0
    expect(stats[:average]).to be > 0
  end
end
