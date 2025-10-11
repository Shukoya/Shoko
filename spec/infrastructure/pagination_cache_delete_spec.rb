# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pagination cache delete' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:home) { tmp_dir }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:epub_path) { File.join(home, 'books/demo.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }
  let(:doc) { Struct.new(:cache_path, :canonical_path).new(cache.cache_path, epub_path) }
  let(:key) { EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal) }

  before do
    @old_home = ENV['HOME']
    @old_cache = ENV['XDG_CACHE_HOME']
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(reader_root)
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
    cache.mutate_layouts! { |layouts| layouts[key] = { 'version' => 1, 'pages' => [] } }
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'removes existing cache entries for a layout' do
    expect(EbookReader::Infrastructure::PaginationCache.exists_for_document?(doc, key)).to be true
    ok = EbookReader::Infrastructure::PaginationCache.delete_for_document(doc, key)
    expect(ok).to be true
    expect(EbookReader::Infrastructure::PaginationCache.exists_for_document?(doc, key)).to be false
  end
end
