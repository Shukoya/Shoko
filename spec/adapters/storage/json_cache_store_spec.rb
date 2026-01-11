# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Shoko::Adapters::Storage::JsonCacheStore do
  it 'writes and reads cached payloads' do
    Dir.mktmpdir do |dir|
      source = Tempfile.new('book')
      source.write('sample')
      source.flush

      store = described_class.new(cache_root: dir)
      sha = 'a' * 64
      chapters = [{ position: 0, raw_content: '<p>hi</p>', title: 'One' }]
      resources = [{ path: 'image.png', data: 'PNG' }]
      layouts = { 'default' => { 'lines' => [1, 2, 3] } }

      written = store.write_payload(
        sha: sha,
        source_path: source.path,
        source_mtime: File.mtime(source.path),
        generated_at: Time.now,
        serialized_book: { title: 'Test' },
        serialized_chapters: chapters,
        serialized_resources: resources,
        serialized_layouts: layouts
      )

      expect(written).to be(true)

      payload = store.fetch_payload(sha, include_resources: true)
      expect(payload).not_to be_nil
      expect(payload.metadata_row['source_sha']).to eq(sha)
      expect(payload.chapters.first['position']).to eq(0)
      expect(payload.resources.first[:path]).to eq('image.png')
      expect(payload.layouts['default']).to eq('lines' => [1, 2, 3])

      manifest = store.list_books
      expect(manifest.first['source_sha']).to eq(sha)
    ensure
      source.close!
    end
  end

  it 'mutates layouts in place' do
    Dir.mktmpdir do |dir|
      store = described_class.new(cache_root: dir)
      sha = 'b' * 64

      store.write_payload(
        sha: sha,
        source_path: __FILE__,
        source_mtime: File.mtime(__FILE__),
        generated_at: Time.now,
        serialized_book: { title: 'Layouts' },
        serialized_chapters: [],
        serialized_resources: [],
        serialized_layouts: { 'layout' => { 'foo' => 'bar' } }
      )

      store.mutate_layouts(sha) do |layouts|
        layouts['layout'] = { 'foo' => 'baz' }
      end

      expect(store.load_layout(sha, 'layout')).to eq('foo' => 'baz')
    end
  end
end
