# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::EPUBDocument do
  let(:epub_path) { '/test.epub' }

  let(:zip_entries) do
    {
      'META-INF/container.xml' => <<~XML,
        <container>
          <rootfiles>
            <rootfile full-path="content.opf" />
          </rootfiles>
        </container>
      XML
      'content.opf' => <<~XML,
        <package>
          <metadata>
            <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title>
            <dc:language xmlns:dc="http://purl.org/dc/elements/1.1/">en</dc:language>
          </metadata>
          <manifest>
            <item id="ch1" href="ch1.html" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
      XML
      'ch1.html' => <<~HTML,
        <html><head><title>Chapter 1</title></head>
        <body><p>This is the content of chapter 1.</p></body></html>
      HTML
    }
  end

  let(:zip_file) do
    double('zip_file').tap do |zip|
      allow(zip).to receive(:read) { |path| zip_entries.fetch(path).dup }
      allow(zip).to receive(:find_entry) { |path| zip_entries.key?(path) }
    end
  end

  before do
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip_file)
    allow(zip_file).to receive(:close)
    allow(zip_file).to receive(:closed?).and_return(false)
  end

  describe '#initialize' do
    it 'loads epub metadata without reading chapters' do
      document = described_class.new(epub_path)

      expect(document.title).to eq('Test Book')
      expect(document.chapter_count).to eq(1)
      expect(zip_file).to have_received(:read).with('META-INF/container.xml')
      expect(zip_file).to have_received(:read).with('content.opf')
      expect(zip_file).not_to have_received(:read).with('ch1.html')
    end

    it 'creates error chapter for corrupted epubs' do
      allow(Zip::File).to receive(:open).and_raise(StandardError.new('Invalid zip'))

      doc = described_class.new(epub_path)
      expect(doc.chapter_count).to eq(1)
      expect(doc.chapters.first.title).to eq('Error Loading')
    end
  end

  describe '#get_chapter' do
    it 'loads chapter content on demand' do
      document = described_class.new(epub_path)
      chapter = document.get_chapter(0)

      expect(chapter).to be_a(EbookReader::Models::Chapter)
      expect(chapter.title).to eq('Chapter 1')
      expect(chapter.lines).to include('This is the content of chapter 1.')
      expect(zip_file).to have_received(:read).with('ch1.html').once
    end

    it 'returns nil for invalid index' do
      document = described_class.new(epub_path)
      expect(document.get_chapter(-1)).to be_nil
      expect(document.get_chapter(10)).to be_nil
    end
  end
end
