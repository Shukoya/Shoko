# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Reader, 'dynamic refresh' do
  let(:epub_path) { '/book.epub' }
  let(:config) { EbookReader::Config.new }
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Test',
                    language: 'en',
                    chapter_count: 1,
                    chapters: [
                      EbookReader::Models::Chapter.new(number: '1', title: 'Ch1', lines: Array.new(50, 'line'), metadata: nil),
                    ])
  end
  subject(:reader) { described_class.new(epub_path, config) }

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter) { |i| doc.chapters[i] }
    allow(EbookReader::BookmarkManager).to receive(:get).and_return([])
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
  end

  it 'detects state change when advancing pages in dynamic mode' do
    config.page_numbering_mode = :dynamic
    reader.instance_variable_set(:@page_manager, EbookReader::Services::PageManager.new(doc, config))
    reader.instance_variable_get(:@page_manager).build_page_map(80, 24)

    old_state = reader.send(:capture_state)
    reader.next_page
    expect(reader.send(:state_changed?, old_state)).to be true
  end
end
