# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::MouseableReader do
  before do
    mock_terminal(width: 80, height: 24)

    # Stub DocumentService to avoid filesystem
    stub_const('EbookReader::Infrastructure::DocumentService', Class.new do
      FakeChapter = Struct.new(:title, :lines)
      class FakeDoc
        def initialize(ch) = (@ch = ch)
        def chapter_count = 1
        def chapters = [@ch]
        def get_chapter(_i) = @ch
        def title = 'Doc'
        def language = 'en'
      end

      def initialize(_path); end

      def load_document
        ch = FakeChapter.new('Ch1', ['l1'])
        FakeDoc.new(ch)
      end
    end)
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
