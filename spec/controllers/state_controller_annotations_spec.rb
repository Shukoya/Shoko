# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::StateController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }
  let(:doc) { double('Doc', chapter_count: 1) }
  let(:term) { double('Term', size: [24, 80], cleanup: nil) }

  class CtnSC
    def initialize(term, svc)
      (@term = term
       @svc = svc)
    end

    def resolve(name)
      return @term if name == :terminal_service
      return @svc if name == :annotation_service

      nil
    end
  end

  it 'refresh_annotations uses AnnotationService and dispatches update' do
    ann = [{ 'text' => 't', 'note' => 'n' }]
    svc = double('AnnotationService', list_for_book: ann)
    sc = described_class.new(state, doc, '/tmp/book.epub', CtnSC.new(term, svc))

    expect(svc).to receive(:list_for_book).with('/tmp/book.epub').and_return(ann)
    sc.refresh_annotations
    expect(state.get(%i[reader annotations])).to eq(ann)
  end
end
