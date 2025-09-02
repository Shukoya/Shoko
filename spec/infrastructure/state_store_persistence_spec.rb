# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'StateStore persistence', :fakefs do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }

  it 'saves config to file' do
    store = EbookReader::Infrastructure::StateStore.new(bus)
    store.set(%i[config view_mode], :single)
    store.save_config
    path = EbookReader::Infrastructure::StateStore::CONFIG_FILE
    expect(File).to exist(path)
    data = JSON.parse(File.read(path))
    expect(data['view_mode']).to eq('single')
  end

  it 'loads config on ObserverStateStore init' do
    # Write a config file first
    dir = EbookReader::Infrastructure::StateStore::CONFIG_DIR
    FileUtils.mkdir_p(dir)
    File.write(EbookReader::Infrastructure::StateStore::CONFIG_FILE, { view_mode: 'single' }.to_json)
    store = EbookReader::Infrastructure::ObserverStateStore.new(bus)
    expect(store.get(%i[config view_mode])).to eq(:single)
  end
end
