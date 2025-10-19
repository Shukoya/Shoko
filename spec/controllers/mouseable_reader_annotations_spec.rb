# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::MouseableReader do
  before do
    mock_terminal(width: 80, height: 24)

    chapter_struct = Struct.new(:title, :lines)
    chapters = [chapter_struct.new('Ch1', ['l1'])]
    stub_document_service(chapters: chapters)
  end

  it 'uses AnnotationService to refresh annotations during init' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    svc = double('AnnotationService')
    allow(svc).to receive(:list_for_book).and_return([{ 'text' => 'a' }])
    container.register(:annotation_service, svc)

    reader = described_class.new('/tmp/fake.epub', nil, container)
    # service should have been called for the given path (once by StateController, once by MouseableReader)
    expect(svc).to have_received(:list_for_book).with('/tmp/fake.epub').at_least(:once)
    expect(reader.state.get(%i[reader annotations])).to eq([{ 'text' => 'a' }])
  end
end
