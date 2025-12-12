# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

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
    payload_path = File.join(cache_root, "#{cache.sha256}.json")

    expect(payload).to be_a(described_class::CachePayload)
    expect(File.exist?(cache.cache_path)).to be(true)
    expect(File.exist?(payload_path)).to be(true)

    pointer = JSON.parse(File.read(cache.cache_path))
    expect(pointer['format']).to eq(EbookReader::Infrastructure::CachePointerManager::POINTER_FORMAT)
    expect(pointer['engine']).to eq(EbookReader::Infrastructure::JsonCacheStore::ENGINE)
    expect(pointer['sha256']).to eq(cache.sha256)

    reloaded = described_class.new(epub_path).load_for_source(strict: true)
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

  it 'rejects unsafe layout keys (prevents path traversal writes)' do
    cache = described_class.new(epub_path)
    cache.write_book!(book_data)

    success = cache.mutate_layouts! do |layouts|
      layouts['../evil'] = { 'version' => 1, 'pages' => [] }
    end

    expect(success).to be(false)
    expect(File.exist?(File.join(cache_root, 'layouts', 'evil.json'))).to be(false)
  end

  it 'returns nil when pointer payload is corrupted' do
    cache = described_class.new(epub_path)
    cache.write_book!(book_data)

    File.write(cache.cache_path, 'corrupt')
    expect do
      described_class.new(cache.cache_path).read_cache(strict: true)
    end.to raise_error(EbookReader::CacheLoadError)
  end

  it 'rejects cache pointer files with invalid sha256 digests' do
    bad_pointer = File.join(tmp_dir, 'invalid.cache')
    File.write(
      bad_pointer,
      JSON.generate(
        {
          'format' => EbookReader::Infrastructure::CachePointerManager::POINTER_FORMAT,
          'version' => EbookReader::Infrastructure::CachePointerManager::POINTER_VERSION,
          'sha256' => '../evil',
          'source_path' => epub_path,
          'generated_at' => Time.now.utc.iso8601,
          'engine' => EbookReader::Infrastructure::JsonCacheStore::ENGINE
        }
      )
    )

    expect { described_class.new(bad_pointer) }.to raise_error(EbookReader::CacheLoadError)
  end

  it 'repairs pointer files when loading via source path after corruption' do
    cache = described_class.new(epub_path)
    cache.write_book!(book_data)

    pointer_path = cache.cache_path
    File.write(pointer_path, 'broken-pointer')

    restored_payload = described_class.new(epub_path).load_for_source(strict: true)
    expect(restored_payload).not_to be_nil

    pointer = JSON.parse(File.read(pointer_path))
    expect(pointer['format']).to eq(EbookReader::Infrastructure::CachePointerManager::POINTER_FORMAT)
    expect(pointer['sha256']).to eq(cache.sha256)
  end
end
