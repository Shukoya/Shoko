# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::Storage::ProgressFileStore do
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

  it 'saves, loads and lists all progress' do
    store = described_class.new(file_writer:, path_service:)
    expect(store.save('/tmp/a.epub', 2, 50)).to be true
    h = store.load('/tmp/a.epub')
    expect(h['chapter']).to eq(2)
    expect(h['line_offset']).to eq(50)
    all = store.load_all
    expect(all).to have_key('/tmp/a.epub')
  end
end
