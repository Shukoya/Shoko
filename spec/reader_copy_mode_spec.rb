# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Reader, 'copy mode' do
  let(:epub_path) { '/book.epub' }
  let(:config) { EbookReader::Config.new }
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Test Book',
                    chapters: [{ title: 'Chapter 1', lines: ['Line 1'] }],
                    chapter_count: 1,
                    language: 'en')
  end
  let(:renderer) { instance_double(EbookReader::UI::ReaderRenderer, render_header: nil, render_footer: nil) }
  let(:reader) { described_class.new(epub_path, config) }

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter).and_return(doc.chapters.first)
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
    reader.instance_variable_set(:@renderer, renderer)
  end

  it 'shows the indicator and waits for input' do
    allow(EbookReader::Terminal).to receive(:read_key_blocking).and_return('x')
    expect(EbookReader::Terminal).to receive(:write).with(24, 1, /copy mode activated!/i)
    reader.enter_copy_mode
    expect(reader.instance_variable_get(:@copy_mode)).to be false
  end
end
