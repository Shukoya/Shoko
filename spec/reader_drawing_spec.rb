# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Reader, 'drawing' do
  let(:epub_path) { '/book.epub' }
  let(:config) { EbookReader::Config.new }
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Test Book',
                    chapters: [
                      { title: 'Chapter 1', lines: ['Line 1'] },
                      { title: 'Chapter 2', lines: ['Line 2'] },
                    ],
                    chapter_count: 2,
                    language: 'en')
  end
  let(:renderer) { instance_double(EbookReader::UI::ReaderRenderer) }
  let(:reader) { described_class.new(epub_path, config) }

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter).and_return(doc.chapters.first)
    allow(EbookReader::Terminal).to receive(:setup)
    allow(EbookReader::Terminal).to receive(:cleanup)
    allow(EbookReader::Terminal).to receive(:start_frame)
    allow(EbookReader::Terminal).to receive(:end_frame)
    allow(EbookReader::Terminal).to receive(:write)
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
    allow(reader).to receive(:loop).and_yield
    reader.instance_variable_set(:@renderer, renderer)
    allow(renderer).to receive(:render_header)
    allow(renderer).to receive(:render_footer)
  end

  context 'when drawing different content screens' do
    it 'draws the help screen' do
      reader.instance_variable_set(:@mode, :help)
      expect(reader).to receive(:draw_help_screen)
      reader.send(:draw_screen)
    end

    it 'draws the ToC screen' do
      reader.instance_variable_set(:@mode, :toc)
      expect(reader).to receive(:draw_toc_screen)
      reader.send(:draw_screen)
    end

    it 'draws the bookmarks screen' do
      reader.instance_variable_set(:@mode, :bookmarks)
      expect(reader).to receive(:draw_bookmarks_screen)
      reader.send(:draw_screen)
    end
  end

  context 'when drawing reading content' do
    it 'draws in split view mode' do
      config.view_mode = :split
      expect(reader).to receive(:draw_split_screen)
      reader.send(:draw_reading_content, 24, 80)
    end

    it 'draws in single view mode' do
      config.view_mode = :single
      expect(reader).to receive(:draw_single_screen)
      reader.send(:draw_reading_content, 24, 80)
    end
  end

  context 'when drawing messages' do
    it 'draws a temporary message to the screen' do
      reader.instance_variable_set(:@message, 'Bookmark Added')
      expect(EbookReader::Terminal).to receive(:write).with(12, 33, /Bookmark Added/)
      reader.send(:draw_screen)
    end
  end
end
