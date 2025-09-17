# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ebook_reader/helpers/opf_processor'

RSpec.describe EbookReader::Helpers::OPFProcessor do
  let(:opf_content) do
    <<~XML
      <?xml version="1.0"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
        <manifest>
          <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml" />
          <item id="part1" href="text/part1.xhtml" media-type="application/xhtml+xml" />
          <item id="chap1" href="text/chapter1.xhtml" media-type="application/xhtml+xml" />
          <item id="chap2" href="text/chapter2.xhtml" media-type="application/xhtml+xml" />
        </manifest>
        <spine toc="ncx">
          <itemref idref="part1" />
          <itemref idref="chap1" />
          <itemref idref="chap2" />
        </spine>
      </package>
    XML
  end

  let(:ncx_content) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <navMap>
          <navPoint id="part-one">
            <navLabel><text>Part One</text></navLabel>
            <content src="text/part1.xhtml" />
            <navPoint id="chapter-1">
              <navLabel><text>Chapter One</text></navLabel>
              <content src="text/chapter1.xhtml" />
            </navPoint>
            <navPoint id="chapter-2">
              <navLabel><text>Chapter Two</text></navLabel>
              <content src="text/chapter2.xhtml#section" />
            </navPoint>
          </navPoint>
        </navMap>
      </ncx>
    XML
  end

  let(:tmp_dir) { @tmp_dir }

  around do |example|
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'content.opf'), opf_content)
      File.write(File.join(dir, 'toc.ncx'), ncx_content)
      @tmp_dir = dir
      example.run
    end
  ensure
    @tmp_dir = nil
  end

  it 'produces hierarchical toc entries and title map' do
    opf_path = File.join(tmp_dir, 'content.opf')
    processor = described_class.new(opf_path)
    manifest = processor.build_manifest_map
    titles = processor.extract_chapter_titles(manifest)

    expect(titles['text/chapter1.xhtml']).to eq('Chapter One')
    expect(titles['text/chapter2.xhtml#section']).to be_nil

    entries = processor.toc_entries
    expect(entries.length).to eq(3)

    part_entry = entries.first
    expect(part_entry[:title]).to eq('Part One')
    expect(part_entry[:level]).to eq(0)
    expect(part_entry[:href]).to eq('text/part1.xhtml')

    chapter_entry = entries[1]
    expect(chapter_entry[:title]).to eq('Chapter One')
    expect(chapter_entry[:level]).to eq(1)
    expect(chapter_entry[:href]).to eq('text/chapter1.xhtml')
  end
end
