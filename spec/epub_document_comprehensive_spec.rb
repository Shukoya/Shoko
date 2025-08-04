# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::EPUBDocument, 'comprehensive' do
  let(:epub_path) { '/comprehensive.epub' }

  def build_document(entries)
    zip = double('zip_file')
    allow(zip).to receive(:read) { |path| entries.fetch(path).dup }
    allow(zip).to receive(:find_entry) { |path| entries.key?(path) }
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip)
    allow(zip).to receive(:close)
    allow(zip).to receive(:closed?).and_return(false)
    described_class.new(epub_path)
  end

  describe 'error recovery' do
    it 'creates error chapter on any exception during parsing' do
      allow(Zip::File).to receive(:open).and_raise(StandardError.new('Generic error'))
      doc = described_class.new(epub_path)
      expect(doc.chapters.first[:title]).to eq('Error Loading')
      expect(doc.chapters.first[:lines].join("\n")).to include('Generic error')
    end

    it 'ensures at least one chapter exists even with empty spine' do
      entries = {
        'META-INF/container.xml' => container_xml('content.opf'),
        'content.opf' => <<~XML,
          <package>
            <metadata></metadata>
            <manifest></manifest>
            <spine></spine>
          </package>
        XML
      }
      doc = build_document(entries)
      expect(doc.chapters).not_to be_empty
      expect(doc.chapters.first[:title]).to match(/Empty Book/)
    end
  end

  describe 'metadata extraction' do
    it 'handles missing title gracefully' do
      entries = {
        'META-INF/container.xml' => container_xml('content.opf'),
        'content.opf' => <<~XML,
          <package>
            <metadata>
              <dc:language xmlns:dc="http://purl.org/dc/elements/1.1/">fr</dc:language>
            </metadata>
            <manifest></manifest>
            <spine></spine>
          </package>
        XML
      }
      doc = build_document(entries)
      expect(doc.title).to eq('comprehensive')
      expect(doc.language).to eq('fr_FR')
    end
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
