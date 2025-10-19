# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe EbookReader::Infrastructure::Repositories::CachedLibraryRepository do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, '.cache', 'reader') }
  let(:epub_path) { File.join(tmp_dir, 'books', 'library.epub') }
  let(:repository) { described_class.new(cache_root: cache_root) }

  before do
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub-data')

    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Library Book',
      language: 'en',
      authors: ['Author'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'First', lines: ['Hi'], metadata: nil, blocks: nil, raw_content: '<p>Hi</p>')],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['OPS/ch1.xhtml'],
      chapter_hrefs: ['OPS/ch1.xhtml'],
      resources: { 'OPS/ch1.xhtml' => '<p>Hi</p>' },
      metadata: { year: 2021 },
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )

    EbookReader::Infrastructure::EpubCache.new(epub_path).write_book!(book)
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it 'lists entries stored in the SQLite cache' do
    results = repository.list_entries
    expect(results.length).to eq(1)
    entry = results.first
    expect(entry[:title]).to eq('Library Book')
    expect(entry[:authors]).to eq('Author')
    expect(entry[:open_path]).to end_with('.cache')
    expect(entry[:epub_path]).to eq(epub_path)
  end

  it 'recreates missing pointer files' do
    pointer_path = Dir[File.join(cache_root, '*.cache')].first
    FileUtils.rm_f(pointer_path)

    results = repository.list_entries
    recreated = results.first[:open_path]
    expect(File.exist?(recreated)).to be(true)

    pointer = JSON.parse(File.read(recreated))
    expect(pointer['sha256']).not_to be_nil
  end
end
