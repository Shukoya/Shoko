# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::PaginationCache do
  include FakeFS::SpecHelpers

  let(:cache_root) { '/home/test/.cache/reader' }
  let(:book_dir) { File.join(cache_root, 'abcd1234') }
  let(:doc) { Struct.new(:cache_dir, :canonical_path).new(book_dir, nil) }
  let(:key) { described_class.layout_key(80, 24, :single, :normal) }

  before do
    ENV['HOME'] = '/home/test'
    ENV['XDG_CACHE_HOME'] = File.join('/home/test', '.cache')
    FileUtils.mkdir_p(book_dir)
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

