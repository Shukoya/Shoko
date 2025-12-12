# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'digest'

RSpec.describe EbookReader::Infrastructure::MarshalCacheStore do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, 'cache') }
  let(:epub_path) { File.join(tmp_dir, 'book.epub') }
  let(:store) { described_class.new(cache_root:) }
  let(:book_data) do
    EbookReader::Infrastructure::EpubCache::BookData.new(
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
  end

  before do
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'content')
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it 'writes and reads payloads and manifests via Marshal' do
    cache = EbookReader::Infrastructure::EpubCache.new(epub_path, cache_root:, store: store)
    payload = cache.write_book!(book_data)
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

  it 'writes payloads atomically (failed write keeps previous data intact)' do
    sha = Digest::SHA256.file(epub_path).hexdigest
    serialized = EbookReader::Infrastructure::EpubCache::Serializer.serialize(book_data, json: false)
    source_mtime = File.mtime(epub_path)
    generated_at = Time.now.utc

    ok = store.write_payload(
      sha: sha,
      source_path: epub_path,
      source_mtime: source_mtime,
      generated_at: generated_at,
      serialized_book: serialized[:book],
      serialized_chapters: serialized[:chapters],
      serialized_resources: serialized[:resources],
      serialized_layouts: {}
    )
    expect(ok).to be(true)

    payload_path = File.join(cache_root, "#{sha}.marshal")
    original_bytes = File.binread(payload_path)

    allow(EbookReader::Infrastructure::AtomicFileWriter).to receive(:write_using).and_wrap_original do |orig, path, binary: false, &block|
      if path == payload_path
        orig.call(path, binary: binary) do |io|
          block.call(io)
          raise 'simulated crash'
        end
      else
        orig.call(path, binary: binary, &block)
      end
    end

    updated_book = book_data.dup
    updated_book.title = 'Updated'
    updated_serialized = EbookReader::Infrastructure::EpubCache::Serializer.serialize(updated_book, json: false)
    failed = store.write_payload(
      sha: sha,
      source_path: epub_path,
      source_mtime: source_mtime,
      generated_at: generated_at,
      serialized_book: updated_serialized[:book],
      serialized_chapters: updated_serialized[:chapters],
      serialized_resources: updated_serialized[:resources],
      serialized_layouts: {}
    )
    expect(failed).to be(false)
    expect(File.binread(payload_path)).to eq(original_bytes)
  end
end
