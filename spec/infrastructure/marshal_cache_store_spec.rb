# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe EbookReader::Infrastructure::MarshalCacheStore do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, 'cache') }
  let(:epub_path) { File.join(tmp_dir, 'book.epub') }
  let(:store) { described_class.new(cache_root:) }

  before do
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'content')
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it 'writes and reads payloads and manifests via Marshal' do
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Marshal Book',
      language: 'en',
      authors: ['Speedy'],
      chapters: [
        EbookReader::Domain::Models::Chapter.new(number: '1', title: 'One',
                                                 lines: ['Hello'], metadata: nil, blocks: nil,
                                                 raw_content: '<p>Hello</p>'),
      ],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['OPS/ch1.xhtml'],
      chapter_hrefs: ['OPS/ch1.xhtml'],
      resources: { 'OPS/ch1.xhtml' => '<p>Hello</p>' },
      metadata: { year: 2024 },
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )

    cache = EbookReader::Infrastructure::EpubCache.new(epub_path, cache_root:, store: store)
    payload = cache.write_book!(book)
    expect(payload).not_to be_nil

    read_payload = cache.read_cache(strict: true)
    expect(read_payload).not_to be_nil
    expect(read_payload.book.title).to eq('Marshal Book')
    pointer = JSON.parse(File.read(cache.cache_path))
    expect(pointer['engine']).to eq(EbookReader::Infrastructure::MarshalCacheStore::ENGINE)

    manifest_rows = described_class.manifest_rows(cache_root)
    expect(manifest_rows.length).to eq(1)
    expect(manifest_rows.first['title']).to eq('Marshal Book')
  end
end
