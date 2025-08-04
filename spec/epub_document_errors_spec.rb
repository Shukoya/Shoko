# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::EPUBDocument, 'error handling' do
  let(:epub_path) { '/books/test.epub' }

  it 'handles Zip::Error during parsing' do
    allow(Zip::File).to receive(:open).and_raise(Zip::Error)
    doc = described_class.new(epub_path)
    expect(doc.chapters.first[:title]).to eq('Error Loading')
  end

  it 'handles missing container.xml' do
    zip = double('zip_file')
    allow(zip).to receive(:read).with('META-INF/container.xml').and_raise(Zip::Error)
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip)
    allow(zip).to receive(:close)
    allow(zip).to receive(:closed?).and_return(false)

    doc = described_class.new(epub_path)
    expect(doc.chapters.first[:title]).to eq('Empty Book')
  end

  it 'handles missing OPF file' do
    entries = { 'META-INF/container.xml' => container_xml('content.opf') }

    zip = double('zip_file')
    allow(zip).to receive(:read) { |path| entries.fetch(path).dup }
    allow(zip).to receive(:find_entry) { |path| path != 'content.opf' && entries.key?(path) }
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip)
    allow(zip).to receive(:close)
    allow(zip).to receive(:closed?).and_return(false)

    doc = described_class.new(epub_path)
    expect(doc.chapters.first[:title]).to eq('Empty Book')
  end

  def container_xml(path)
    <<~XML
      <container>
        <rootfiles>
          <rootfile full-path="#{path}" />
        </rootfiles>
      </container>
    XML
  end
end
