# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe EbookReader::Infrastructure::EpubCache do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:epub_path) { File.join(tmp_dir, 'book.epub') }
  let(:cache_root) { File.join(tmp_dir, '.cache', 'reader') }
  let(:book_data) do
    EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Spec Book',
      language: 'en_US',
      authors: ['Author'],
      chapters: [
        EbookReader::Domain::Models::Chapter.new(
          number: '1',
          title: 'Chapter 1',
          lines: ['hello'],
          metadata: nil,
          blocks: nil,
          raw_content: '<p>hello</p>'
        ),
      ],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['xhtml/1.xhtml'],
      chapter_hrefs: ['xhtml/1.xhtml'],
      resources: {
        'META-INF/container.xml' => '<xml/>',
        'OPS/content.opf' => '<xml/>',
        'xhtml/1.xhtml' => '<p>hello</p>',
      },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )
  end

  before do
    File.write(epub_path, 'fake-epub-data')
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'writes and reloads a cache payload for an EPUB source' do
    cache = described_class.new(epub_path)
    payload = cache.write_book!(book_data)
    expect(payload).to be_a(described_class::CachePayload)
    expect(File.exist?(cache.cache_path)).to be(true)

    reloaded = cache.load_for_source(strict: true)
    expect(reloaded.book.title).to eq('Spec Book')
    expect(reloaded.book.chapters.first.lines).to eq(['hello'])
  end

  it 'stores layout metadata inside the cache file' do
    cache = described_class.new(epub_path)
    cache.write_book!(book_data)

    cache.mutate_layouts! do |layouts|
      layouts['layout-key'] = { 'version' => 1, 'pages' => [{ 'chapter_index' => 0 }] }
    end

    layout = cache.load_layout('layout-key')
    expect(layout['pages']).to eq([{ 'chapter_index' => 0 }])
  end

  it 'invalidates corrupted cache files' do
    cache = described_class.new(epub_path)
    cache.write_book!(book_data)

    File.write(cache.cache_path, 'corrupt')
    expect(cache.read_cache(strict: true)).to be_nil
    expect(File.exist?(cache.cache_path)).to be(false)
  end
end
