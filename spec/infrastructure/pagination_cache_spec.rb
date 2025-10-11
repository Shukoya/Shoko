# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::PaginationCache do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, '.cache', 'reader') }
  let(:epub_path) { File.join(tmp_dir, 'demo.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }
  let(:doc) { Struct.new(:cache_path, :canonical_path).new(cache.cache_path, epub_path) }
  let(:key) { described_class.layout_key(80, 24, :single, :normal) }

  before do
    @old_home = ENV['HOME']
    @old_cache = ENV['XDG_CACHE_HOME']
    ENV['HOME'] = tmp_dir
    ENV['XDG_CACHE_HOME'] = File.join(tmp_dir, '.cache')
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub-data')
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Demo',
      language: 'en_US',
      authors: ['Author'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Demo', lines: ['one'], metadata: nil, blocks: nil, raw_content: '<p>one</p>')],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['xhtml/1.xhtml'],
      chapter_hrefs: ['xhtml/1.xhtml'],
      resources: { 'META-INF/container.xml' => '<xml/>' },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )
    cache.write_book!(book)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'saves and loads compact pagination entries for a layout' do
    pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 3, 'start_line' => 0, 'end_line' => 24 },
      { 'chapter_index' => 0, 'page_in_chapter' => 1, 'total_pages_in_chapter' => 3, 'start_line' => 25, 'end_line' => 49 },
    ]

    ok = described_class.save_for_document(doc, key, pages)
    expect(ok).to be true
    expect(described_class.exists_for_document?(doc, key)).to be true

    loaded = described_class.load_for_document(doc, key)
    expect(loaded).to be_a(Array)
    expect(loaded.length).to eq(2)
    expect(loaded.first[:start_line]).to eq(0)
    expect(loaded.last[:end_line]).to eq(49)
  end
end
