# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Services::StateService do
  let(:config) do
    instance_double(EbookReader::Config, page_numbering_mode: :absolute, view_mode: :single)
  end
  let(:doc) { instance_double(EbookReader::EPUBDocument) }
  let(:reader) do
    instance_double(
      EbookReader::Reader,
      path: '/book.epub',
      config: config,
      doc: doc,
      current_chapter: 1,
      single_page: 5
    )
  end

  subject(:service) { described_class.new(reader) }

  describe '#save_progress' do
    it 'persists reader progress via ProgressManager' do
      expect(EbookReader::ProgressManager).to receive(:save).with('/book.epub', 1, 5)
      service.save_progress
    end
  end
end
