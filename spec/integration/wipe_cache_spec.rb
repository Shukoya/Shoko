# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Wipe Cache setting' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:home) { tmp_dir }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:config_dir) { File.join(home, '.config', 'reader') }
  let(:epub_cache_file) { File.join(config_dir, 'epub_cache.json') }
  let(:recent_file) { File.join(config_dir, 'recent.json') }

  before do
    # Simulate HOME and XDG_CACHE_HOME
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    stub_const('EbookReader::EPUBFinder::CACHE_FILE', epub_cache_file)
    stub_const('EbookReader::RecentFiles::RECENT_FILE', recent_file)
    allow(EbookReader::EPUBFinder).to receive(:clear_cache) do
      FileUtils.rm_f(EbookReader::EPUBFinder::CACHE_FILE)
    end

    FileUtils.mkdir_p(reader_cache_root)
    File.write(File.join(reader_cache_root, 'dummysha.cache'), 'cache-bytes')

    FileUtils.mkdir_p(config_dir)
    File.write(epub_cache_file, '{"timestamp":"2020-01-01T00:00:00Z","files":[]}')
    File.write(recent_file, '[{"path":"/book.epub","name":"Book","accessed":"2020-01-01T00:00:00Z"}]')
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'wipes epub cache directory and scan cache file' do
    mm = EbookReader::MainMenu.new
    # Ensure settings bindings are in place and active
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    6.times { dispatcher.handle_key('j') }
    dispatcher.handle_key(' ')

    expect(File).not_to exist(reader_cache_root)
    expect(File).not_to exist(epub_cache_file)
    expect(File).not_to exist(recent_file)

    # Scanner state resets and message was set
    controller = mm.instance_variable_get(:@controller)
    catalog = controller.catalog
    expect(catalog.entries).to eq([])
    expect(catalog.scan_status).to eq(:idle)
    expect(catalog.scan_message).to match(/wiped/i)
  end
end
