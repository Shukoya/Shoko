# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Reader do
  let(:epub_path) { '/test.epub' }
  let(:config) { EbookReader::Config.new }
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Test Book',
                    language: 'en',
                    chapter_count: 2,
                    chapters: [
                      EbookReader::Models::Chapter.new(number: '1', title: 'Ch1',
                                                       lines: Array.new(100, 'Line'), metadata: nil),
                      EbookReader::Models::Chapter.new(number: '2', title: 'Ch2',
                                                       lines: Array.new(50, 'Line'), metadata: nil),
                    ])
  end
  let(:reader) { described_class.new(epub_path, config) }

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter) { |i| doc.chapters[i] }
    allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
    allow(EbookReader::Terminal).to receive(:write)
    allow(EbookReader::BookmarkManager).to receive(:get).and_return([])
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
    allow(EbookReader::ProgressManager).to receive(:save)
    reader.send(:update_page_map, 80, 24)
  end

  describe 'page numbering' do
    context 'with absolute page numbering' do
      before do
        config.page_numbering_mode = :absolute
      end

      it 'calculates the correct global page number' do
        reader.instance_variable_set(:@current_chapter, 1)
        reader.instance_variable_set(:@single_page, 10)
        pages = reader.send(:calculate_current_pages)
        expect(pages[:current]).to eq(6)
      end
    end

    context 'with dynamic page numbering' do
      before do
        config.page_numbering_mode = :dynamic
      end

      it 'calculates the correct page number within the chapter' do
        reader.instance_variable_set(:@current_chapter, 0)
        reader.instance_variable_set(:@single_page, 30)
        pages = reader.send(:calculate_current_pages)
        expect(pages[:current]).to eq(2)
        expect(pages[:total]).to eq(7)
      end
    end

    it 'toggles the page numbering mode' do
      expect(config.page_numbering_mode).to eq(:absolute)
      reader.send(:toggle_page_numbering_mode)
      expect(config.page_numbering_mode).to eq(:dynamic)
      reader.send(:toggle_page_numbering_mode)
      expect(config.page_numbering_mode).to eq(:absolute)
    end
  end
end
