# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::BookmarkFileStore do
  include FakeFS::SpecHelpers

  let(:config_dir) { '/config/reader' }
  let(:file_path) { File.join(config_dir, 'bookmarks.json') }
  let(:file_writer) do
    instance_double('FileWriter').tap do |writer|
      allow(writer).to receive(:write) do |path, payload|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, payload)
      end
    end
  end
  let(:path_service) do
    instance_double('PathService', reader_config_root: config_dir).tap do |service|
      allow(service).to receive(:reader_config_path) do |*segments|
        File.join(config_dir, *segments)
      end
    end
  end

  it 'adds, lists and deletes bookmarks' do
    store = described_class.new(file_writer:, path_service:)
    data = EbookReader::Domain::Models::BookmarkData.new(path: '/tmp/a.epub', chapter: 1, line_offset: 10, text: 'x')
    created = store.add(data)
    expect(created).to be_a(Hash)
    expect(File).to exist(file_path)

    list = store.get('/tmp/a.epub')
    expect(list.length).to eq(1)
    expect(list.first.chapter_index).to eq(1)
    expect(list.first.line_offset).to eq(10)

    bm = list.first
    expect(store.delete('/tmp/a.epub', bm)).to be true
    expect(store.get('/tmp/a.epub')).to be_empty
  end

  it 'sanitizes bookmark text snippets' do
    store = described_class.new(file_writer:, path_service:)
    dangerous = "hi\u009B31mX\e]2;HACK\a"
    data = EbookReader::Domain::Models::BookmarkData.new(path: '/tmp/a.epub', chapter: 1, line_offset: 10, text: dangerous)
    created = store.add(data)
    expect(created).to include('text' => 'hiX')

    list = store.get('/tmp/a.epub')
    expect(list.length).to eq(1)
    expect(list.first.text_snippet).to eq('hiX')
    expect(list.first.text_snippet).not_to include("\u009B")
    expect(list.first.text_snippet).not_to include("\e")
  end
end
