# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::LayoutService do
  let(:service) { described_class.new(EbookReader::Domain::ContainerFactory.create_test_container) }

  it 'calculates metrics for single and split view' do
    col, height = service.calculate_metrics(100, 40, :single)
    expect(col).to be_between(30, 120)
    expect(height).to eq(38)

    col2, height2 = service.calculate_metrics(100, 40, :split)
    expect(col2).to be <= 50
    expect(height2).to eq(38)
  end

  it 'adjusts for line spacing' do
    expect(service.adjust_for_line_spacing(20, :normal)).to eq(20)
    expect(service.adjust_for_line_spacing(20, :relaxed)).to eq(10)
  end
end
