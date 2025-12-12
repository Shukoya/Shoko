# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::ReaderController do
  before do
    mock_terminal(width: 80, height: 24)

    chapter_struct = Struct.new(:title, :lines)
    chapters = [
      chapter_struct.new('Chapter One', ['chapter one']),
      chapter_struct.new('Chapter Two', ['chapter two']),
    ]
    toc_entries = [
      EbookReader::Domain::Models::TOCEntry.new(title: 'Part One', href: 'part1.xhtml', level: 0,
                                                chapter_index: nil, navigable: false),
      EbookReader::Domain::Models::TOCEntry.new(title: 'Chapter One', href: 'chapter1.xhtml', level: 1,
                                                chapter_index: 0, navigable: true),
      EbookReader::Domain::Models::TOCEntry.new(title: 'Chapter Two', href: 'chapter2.xhtml', level: 1,
                                                chapter_index: 1, navigable: true),
    ]
    stub_document_service(chapters:, doc_attrs: { title: 'Demo', toc_entries: toc_entries })
  end

  it 'skips non-navigable TOC headings when moving through TOC' do
    controller = described_class.new('/tmp/fake.epub')
    controller.toc_down
    expect(controller.state.get(%i[reader toc_selected])).to eq(1)
    expect(controller.state.get(%i[reader sidebar_toc_selected])).to eq(1)

    controller.state.set(%i[reader toc_selected], 2)
    controller.state.set(%i[reader sidebar_toc_selected], 2)
    controller.toc_up
    expect(controller.state.get(%i[reader toc_selected])).to eq(1)
    expect(controller.state.get(%i[reader sidebar_toc_selected])).to eq(1)
  end
end
