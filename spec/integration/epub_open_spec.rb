# frozen_string_literal: true

require 'spec_helper'
require 'zip'

RSpec.describe 'EPUB open via stdlib ZIP' do
  include ZipTestBuilder

  def build_minimal_epub
    container_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
    XML

    opf = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Test Book</dc:title>
          <dc:language>en</dc:language>
          <dc:creator>Jane Doe</dc:creator>
          <dc:date>2023</dc:date>
        </metadata>
        <manifest>
          <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="ch1"/>
        </spine>
      </package>
    XML

    chapter = <<~HTML
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter One</title></head>
        <body><h1>Chapter 1</h1><p>Hello world</p></body>
      </html>
    HTML

    ZipTestBuilder.build_zip([
                               { name: 'META-INF/container.xml', data: container_xml, method: :deflate },
                               { name: 'OEBPS/content.opf', data: opf, method: :deflate },
                               { name: 'OEBPS/ch1.xhtml', data: chapter, method: :deflate },
                             ], comment: 'minimal epub')
  end

  def build_malicious_epub
    container_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
    XML

    opf = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Test&#x9b;31mBook</dc:title>
          <dc:language>en</dc:language>
          <dc:creator>Jane&#x1b;[31mDoe</dc:creator>
          <dc:date>2023</dc:date>
        </metadata>
        <manifest>
          <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="ch1"/>
        </spine>
      </package>
    XML

    chapter = <<~HTML
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter&#x9b;31mOne</title></head>
        <body>
          <h1>Chapter 1</h1>
          <p>Hello &#x1b;[31mworld&#x1b;[0m</p>
          <p>OSC: \e]2;HACK\a end</p>
        </body>
      </html>
    HTML

    ZipTestBuilder.build_zip([
                               { name: 'META-INF/container.xml', data: container_xml, method: :deflate },
                               { name: 'OEBPS/content.opf', data: opf, method: :deflate },
                               { name: 'OEBPS/ch1.xhtml', data: chapter, method: :deflate },
                             ], comment: 'malicious epub')
  end

  it 'parses metadata and first chapter' do
    data = build_minimal_epub
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'book.epub')
      File.binwrite(path, data)
      cache_root = File.join(dir, '.cache', 'reader')
      allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)

      doc = EbookReader::EPUBDocument.new(path)
      expect(doc.title).to eq('Test Book')
      expect(doc.chapter_count).to eq(1)

      ch = doc.get_chapter(0)
      expect(ch).not_to be_nil
      expect(ch.title).to eq('Chapter One')
      expect(ch.lines.join("\n")).to include('Hello world')
    end
  end

  it 'sanitizes terminal control sequences from untrusted EPUB content' do
    data = build_malicious_epub
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'book.epub')
      File.binwrite(path, data)
      cache_root = File.join(dir, '.cache', 'reader')
      allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)

      doc = EbookReader::EPUBDocument.new(path)
      expect(doc.title).to eq('TestBook')
      expect(doc.chapter_count).to eq(1)

      ch = doc.get_chapter(0)
      expect(ch.title).to eq('ChapterOne')
      rendered = ch.lines.join("\n")
      expect(rendered).to include('Hello world')
      expect(rendered).not_to include("\e")
      expect(rendered).not_to include("\u009B")
    end
  end
end
