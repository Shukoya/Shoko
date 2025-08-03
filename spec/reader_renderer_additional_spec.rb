# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::ReaderRenderer do
  let(:config) { instance_double(EbookReader::Config, show_page_numbers: false, page_numbering_mode: :absolute) }
  let(:renderer) { described_class.new(config) }
  let(:doc) { instance_double(EbookReader::EPUBDocument, title: 'Title', chapter_count: 2, language: 'en') }

  before do
    allow(EbookReader::Terminal).to receive(:write)
  end

  describe '#render_footer' do
    it 'skips page numbers in single view when disabled' do
      pages = { current: 1, total: 10 }
      renderer.render_footer(24, 80, doc, 0, pages, :single, :read, :normal, [])
      expect(EbookReader::Terminal).not_to have_received(:write)
    end

    it 'skips second footer line when height is small' do
      pages = { current: 1, total: 10 }
      renderer.render_footer(3, 80, doc, 0, pages, :split, :read, :normal, [])
      expect(EbookReader::Terminal).to have_received(:write).exactly(3).times
    end
  end
end
