# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::WrappingService do
  let(:container) { EbookReader::Domain::DependencyContainer.new }
  let(:formatting_service) { instance_double(EbookReader::Domain::Services::FormattingService) }
  let(:document) { instance_double('Document') }

  before do
    container.register(:formatting_service, formatting_service)
    container.register(:document, document)
  end

  it 'delegates to formatting service when available' do
    display_line = EbookReader::Domain::Models::DisplayLine.new(text: 'Formatted line', segments: [], metadata: {})
    expect(formatting_service).to receive(:wrap_window)
      .with(document, 0, 40, offset: 0, length: 2)
      .and_return([display_line])

    service = described_class.new(container)
    result = service.wrap_window(['raw line'], 0, 40, 0, 2)
    expect(result).to eq(['Formatted line'])
  end

  it 'falls back to raw wrapping when formatting returns nil' do
    allow(formatting_service).to receive(:wrap_window).and_return(nil)
    service = described_class.new(container)

    lines = ['long words go here']
    result = service.wrap_window(lines, 0, 5, 0, 3)
    expect(result).to include('long', 'words')
  end
end
