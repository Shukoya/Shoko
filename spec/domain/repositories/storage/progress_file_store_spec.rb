# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::ProgressFileStore do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:config_dir) { File.join(home, '.config', 'reader') }

  before do
    ENV['HOME'] = home
    FileUtils.mkdir_p(config_dir)
  end

  it 'saves, loads and lists all progress' do
    store = described_class.new
    expect(store.save('/tmp/a.epub', 2, 50)).to be true
    h = store.load('/tmp/a.epub')
    expect(h['chapter']).to eq(2)
    expect(h['line_offset']).to eq(50)
    all = store.load_all
    expect(all).to have_key('/tmp/a.epub')
  end
end
