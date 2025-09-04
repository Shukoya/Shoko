# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Wipe Cache setting' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:config_dir) { File.join(home, '.config', 'reader') }
  let(:epub_cache_file) { File.join(config_dir, 'epub_cache.json') }
  let(:recent_file) { File.join(config_dir, 'recent.json') }

  before do
    # Simulate HOME and XDG_CACHE_HOME
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    stub_const('EbookReader::EPUBFinder::CACHE_FILE', epub_cache_file)
    stub_const('EbookReader::RecentFiles::RECENT_FILE', recent_file)

    FileUtils.mkdir_p(reader_cache_root)
    FileUtils.mkdir_p(File.join(reader_cache_root, 'dummysha'))
    File.write(File.join(reader_cache_root, 'dummysha', 'manifest.json'), '{"ok":true}')

    FileUtils.mkdir_p(config_dir)
    File.write(epub_cache_file, '{"timestamp":"2020-01-01T00:00:00Z","files":[]}')
    File.write(recent_file, '[{"path":"/book.epub","name":"Book","accessed":"2020-01-01T00:00:00Z"}]')
  end

  it 'wipes epub cache directory and scan cache file' do
    mm = EbookReader::MainMenu.new
    # Ensure settings bindings are in place and active
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    # Press key 6 (Wipe Cache)
    dispatcher.handle_key('6')

    expect(File).not_to exist(reader_cache_root)
    expect(File).not_to exist(epub_cache_file)
    expect(File).not_to exist(recent_file)

    # Scanner state resets and message was set
    expect(mm.scanner.epubs).to eq([])
    expect(mm.scanner.scan_status).to eq(:idle)
    expect(mm.scanner.scan_message).to match(/wiped/i)
  end
end
