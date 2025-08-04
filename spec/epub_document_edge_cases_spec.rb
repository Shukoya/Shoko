# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::EPUBDocument, 'edge cases' do
  let(:epub_path) { '/edge_case.epub' }

  def build_document(entries)
    zip = double('zip_file')
    allow(zip).to receive(:read) { |path| entries.fetch(path).dup }
    allow(zip).to receive(:find_entry) { |path| entries.key?(path) }
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip)
    allow(zip).to receive(:close)
    allow(zip).to receive(:closed?).and_return(false)
    described_class.new(epub_path)
  end

  it 'handles corrupted container.xml' do
    doc = build_document('META-INF/container.xml' => '<invalid xml')
    expect(doc.chapters.first[:title]).to match(/Error Loading|Empty Book/)
  end

  it 'handles OPF with missing manifest items' do
    entries = {
      'META-INF/container.xml' => container_xml('content.opf'),
      'content.opf' => <<~XML,
        <package>
          <metadata>
            <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test</dc:title>
          </metadata>
          <manifest></manifest>
          <spine>
            <itemref idref="missing"/>
          </spine>
        </package>
      XML
    }
    doc = build_document(entries)
    expect(doc.chapters).not_to be_empty
  end

  it 'handles HTML files with BOM' do
    entries = {
      'META-INF/container.xml' => container_xml('content.opf'),
      'content.opf' => <<~XML,
        <package>
          <manifest>
            <item id="ch1" href="ch1.html" />
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
      XML
      'ch1.html' => "\uFEFF<html><body>Test</body></html>",
    }
    doc = build_document(entries)
    expect(doc.chapters).not_to be_empty
  end

  it 'handles missing rootfile in container' do
    doc = build_document('META-INF/container.xml' => '<container></container>')
    expect(doc.chapters).not_to be_empty
    expect(doc.chapters.first[:title]).to match(/Empty Book|Error/)
  end

  it 'handles file read errors in chapters' do
    entries = {
      'META-INF/container.xml' => container_xml('content.opf'),
      'content.opf' => <<~XML,
        <package>
          <manifest>
            <item id="ch1" href="ch1.html" />
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
      XML
    }

    zip = double('zip_file')
    allow(zip).to receive(:read) do |path|
      raise Errno::ENOENT if path == 'ch1.html'

      entries.fetch(path).dup
    end
    allow(zip).to receive(:find_entry) { |path| entries.key?(path) }
    allow(Zip::File).to receive(:open).with(epub_path).and_return(zip)
    allow(zip).to receive(:close)
    allow(zip).to receive(:closed?).and_return(false)

    doc = described_class.new(epub_path)
    expect(doc.chapters).not_to be_empty
  end

  def container_xml(full_path)
    <<~XML
      <container>
        <rootfiles>
          <rootfile full-path="#{full_path}" />
        </rootfiles>
      </container>
    XML
  end
end
