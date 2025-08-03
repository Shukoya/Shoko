# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::ReaderRenderer do
  let(:config) { instance_double(EbookReader::Config, show_page_numbers: true, page_numbering_mode: :absolute) }
  let(:renderer) { described_class.new(config) }
  let(:doc) { instance_double(EbookReader::EPUBDocument, title: 'Title', chapter_count: 2, language: 'en') }

  before do
    allow(EbookReader::Terminal).to receive(:write)
  end

  describe '#render_split_view_footer' do
    it 'includes second footer line when height is sufficient' do
      renderer.send(:render_split_view_footer, 5, 80, doc, 0, :split, :normal, [])
      expect(EbookReader::Terminal).to have_received(:write).at_least(5).times
    end

    it 'skips second footer line when height is too small' do
      allow(EbookReader::Terminal).to receive(:write)
      renderer.send(:render_split_view_footer, 3, 80, doc, 0, :split, :normal, [])
      expect(EbookReader::Terminal).to have_received(:write).exactly(3).times
    end
  end

  describe '#render_second_footer_line' do
    it 'writes title and language' do
      renderer.send(:render_second_footer_line, 10, 80, doc)
      expect(EbookReader::Terminal).to have_received(:write).twice
    end
  end
end
