# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe EbookReader::Infrastructure::EpubCache, 'marshal engine default' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, 'cache') }
  let(:epub_path) { File.join(tmp_dir, 'book.epub') }

  before do
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'stub')
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  def book_data
    EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Marshal Default',
      language: 'en',
      authors: ['Test Author'],
      chapters: [
        EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Chap', lines: ['Hello'], metadata: { foo: 'bar' },
                                                 blocks: nil, raw_content: '<p>Hello</p>'),
      ],
      toc_entries: [
        EbookReader::Domain::Models::TOCEntry.new(title: 'Start', href: 'OPS/ch1.xhtml', level: 0, chapter_index: 0, navigable: true),
      ],
      opf_path: 'OPS/content.opf',
      spine: ['OPS/ch1.xhtml'],
      chapter_hrefs: ['OPS/ch1.xhtml'],
      resources: { 'OPS/ch1.xhtml' => '<p>Hello</p>' },
      metadata: { year: 2024 },
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )
  end

  it 'writes and reads using marshal engine by default' do
    cache = described_class.new(epub_path, cache_root:)
    cache.write_book!(book_data)

    pointer_path = cache.cache_path
    expect(File).to exist(pointer_path)
    pointer = JSON.parse(File.read(pointer_path))
    expect(pointer['engine']).to eq('marshal')

    payload = cache.read_cache(strict: true)
    expect(payload).not_to be_nil
    expect(payload.book.title).to eq('Marshal Default')
    expect(payload.book.authors).to eq(['Test Author'])
    expect(payload.book.metadata).to include(year: 2024).or include('year' => 2024)
    expect(payload.book.chapters.first.lines).to eq(['Hello'])
  end
end
