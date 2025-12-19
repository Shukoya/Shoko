# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::AnnotationFileStore do
  include FakeFS::SpecHelpers

  let(:config_dir) { '/config/reader' }
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

  it 'adds, updates, lists and deletes annotations' do
    store = described_class.new(file_writer:, path_service:)
    path = '/tmp/book.epub'
    ok = store.add(path, 't', 'n', { start: 1, end: 2 }, 0, { current: 1, total: 100, type: :single })
    expect(ok).to be true
    list = store.get(path)
    expect(list.length).to eq(1)
    id = list.first['id']
    expect(store.update(path, id, 'changed')).to be true
    list2 = store.get(path)
    expect(list2.first['note']).to eq('changed')
    expect(store.delete(path, id)).to be true
    expect(store.get(path)).to be_empty
  end

  it 'sanitizes annotation text and notes' do
    store = described_class.new(file_writer:, path_service:)
    path = '/tmp/book.epub'
    ok = store.add(path, "t\u009B31mX", "n\e]2;HACK\a", { start: 1, end: 2 }, 0)
    expect(ok).to be true

    list = store.get(path)
    expect(list.length).to eq(1)
    expect(list.first['text']).to eq('tX')
    expect(list.first['note']).to eq('n')
    expect(list.first['text']).not_to include("\u009B")
    expect(list.first['note']).not_to include("\e")
  end
end
