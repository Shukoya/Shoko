# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::AnnotationFileStore do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:config_dir) { File.join(home, '.config', 'reader') }

  before do
    ENV['HOME'] = home
    FileUtils.mkdir_p(config_dir)
  end

  it 'adds, updates, lists and deletes annotations' do
    store = described_class.new
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
end
