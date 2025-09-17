# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ebook_reader/helpers/opf_processor'

RSpec.describe EbookReader::Helpers::OPFProcessor do
  let(:opf_content) do
    <<~XML
      <?xml version="1.0"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
        <manifest>
          <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml" />
          <item id="main" href="text/book.xhtml" media-type="application/xhtml+xml" />
        </manifest>
        <spine toc="ncx">
          <itemref idref="main" />
        </spine>
      </package>
    XML
  end

  let(:xhtml_content) do
    <<~HTML
      <html xmlns="http://www.w3.org/1999/xhtml">
        <body>
          <div id="part">
            <h1>KOSCHUTZKE, ODDITY, TANGO</h1>
          </div>
          <div id="chapter">
            <h2>K. 67 – Crash Program</h2>
          </div>
        </body>
      </html>
    HTML
  end

  let(:ncx_content) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <navMap>
          <navPoint id="part">
            <navLabel><text>c01</text></navLabel>
            <content src="text/book.xhtml#part" />
            <navPoint id="chapter">
              <navLabel><text>c02</text></navLabel>
              <content src="text/book.xhtml#chapter" />
            </navPoint>
          </navPoint>
        </navMap>
      </ncx>
    XML
  end

  around do |example|
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'content.opf'), opf_content)
      FileUtils.mkdir_p(File.join(dir, 'text'))
      File.write(File.join(dir, 'text', 'book.xhtml'), xhtml_content)
      File.write(File.join(dir, 'toc.ncx'), ncx_content)
      @tmp_dir = dir
      example.run
    end
  ensure
    @tmp_dir = nil
  end

  it 'extracts titles from the target document when navLabels are placeholders' do
    processor = described_class.new(File.join(@tmp_dir, 'content.opf'))
    manifest = processor.build_manifest_map
    processor.extract_chapter_titles(manifest)

    entries = processor.toc_entries
    expect(entries.length).to eq(2)
    expect(entries.first[:title]).to eq('KOSCHUTZKE, ODDITY, TANGO')
    expect(entries.last[:title]).to eq('K. 67 – Crash Program')
  end
end
