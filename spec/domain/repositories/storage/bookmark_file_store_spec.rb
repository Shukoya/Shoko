# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::BookmarkFileStore do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:config_dir) { File.join(home, '.config', 'reader') }
  let(:file_path) { File.join(config_dir, 'bookmarks.json') }

  before do
    ENV['HOME'] = home
    FileUtils.mkdir_p(config_dir)
  end

  it 'adds, lists and deletes bookmarks' do
    store = described_class.new
    data = EbookReader::Domain::Models::BookmarkData.new(path: '/tmp/a.epub', chapter: 1, line_offset: 10, text: 'x')
    expect(store.add(data)).to be true
    expect(File).to exist(file_path)

    list = store.get('/tmp/a.epub')
    expect(list.length).to eq(1)
    expect(list.first.chapter_index).to eq(1)
    expect(list.first.line_offset).to eq(10)

    bm = list.first
    expect(store.delete('/tmp/a.epub', bm)).to be true
    expect(store.get('/tmp/a.epub')).to be_empty
  end
end

