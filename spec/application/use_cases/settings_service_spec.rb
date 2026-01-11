# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Application::UseCases::SettingsService do
  around do |example|
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, 'config')
      cache_dir = File.join(dir, 'cache')
      FileUtils.mkdir_p(config_dir)
      FileUtils.mkdir_p(cache_dir)
      with_env('XDG_CONFIG_HOME' => config_dir, 'XDG_CACHE_HOME' => cache_dir) { example.run }
    end
  end

  it 'toggles reader configuration values' do
    state = Shoko::Application::Infrastructure::ObserverStateStore.new(
      Shoko::Application::Infrastructure::EventBus.new
    )
    container = FakeContainer.new(
      state_store: state,
      terminal_service: instance_double('TerminalService')
    )

    service = described_class.new(container)
    expect(service.toggle_view_mode).to eq(:single)
    expect(state.get(%i[config view_mode])).to eq(:single)

    service.toggle_page_numbers
    expect(state.get(%i[config show_page_numbers])).to eq(false)
  end

  it 'wipes caches and updates the catalog' do
    state = Shoko::Application::Infrastructure::ObserverStateStore.new(
      Shoko::Application::Infrastructure::EventBus.new
    )
    catalog = double('Catalog', update_entries: nil)
    allow(catalog).to receive(:scan_status=)
    allow(catalog).to receive(:scan_message=)

    wrapping_service = double('WrappingService', clear_cache: nil)

    cache_root = Shoko::Adapters::Storage::CachePaths.cache_root
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(cache_root, 'dummy'), 'x')

    container = FakeContainer.new(
      state_store: state,
      terminal_service: instance_double('TerminalService'),
      wrapping_service: wrapping_service,
      catalog_service: catalog
    )

    allow(Shoko::Adapters::BookSources::EPUBFinder).to receive(:clear_cache)

    service = described_class.new(container)
    message = service.wipe_cache(catalog: catalog)
    expect(message).to match(/cache/i)
  end
end
