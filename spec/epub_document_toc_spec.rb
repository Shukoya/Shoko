# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/epub_document'
require 'ebook_reader/domain/models/toc_entry'

RSpec.describe EbookReader::EPUBDocument do
  describe '#assign_toc_entries' do
    it 'creates navigable entries only for chapter levels and preserves part headings' do
      doc = described_class.allocate
      doc.instance_variable_set(:@opf_path, 'OPS/content.opf')
      chapter_refs = [
        EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Part One', lines: [], metadata: nil,
                                                 blocks: nil, raw_content: '<html/>'),
        EbookReader::Domain::Models::Chapter.new(number: '2', title: 'Chapter One', lines: [], metadata: nil,
                                                 blocks: nil, raw_content: '<html/>'),
      ]
      doc.instance_variable_set(:@chapters, chapter_refs)
      doc.instance_variable_set(:@chapter_hrefs, ['OPS/text/part1.xhtml', 'OPS/text/chapter1.xhtml'])
      doc.instance_variable_set(:@toc_entries, [])

      entries = [
        { title: 'Part One', href: 'text/part1.xhtml', level: 0 },
        { title: 'Chapter One', href: 'text/chapter1.xhtml', level: 1 },
      ]

      doc.send(:assign_toc_entries, entries)

      toc = doc.toc_entries
      expect(toc.length).to eq(2)
      expect(toc.first.title).to eq('Part One')
      expect(toc.first.navigable).to be(true)
      expect(toc.first.chapter_index).to eq(0)

      expect(toc.last.title).to eq('Chapter One')
      expect(toc.last.navigable).to be(true)
      expect(toc.last.chapter_index).to eq(1)
    end
  end
end
