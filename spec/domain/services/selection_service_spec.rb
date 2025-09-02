# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::SelectionService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:coordinate_service) { EbookReader::Domain::Services::CoordinateService.new(container) }
  let(:service) { described_class.new(container) }

  before do
    allow(container).to receive(:resolve).with(:coordinate_service).and_return(coordinate_service)
  end

  it 'extracts text across multiple lines within bounds' do
    rendered_lines = {
      '10_5_15' => { row: 10, col: 5, col_end: 15, width: 11, text: 'hello world' },
      '11_5_15' => { row: 11, col: 5, col_end: 15, width: 11, text: 'selection ok' },
    }
    range = { start: { x: 7, y: 9 }, end: { x: 12, y: 10 } } # mouse coords (y are decremented in normalize)
    text = service.extract_text(range, rendered_lines)
    expect(text).to be_a(String)
    expect(text).not_to be_empty
  end
end
