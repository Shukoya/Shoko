# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library instant open' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:book_dir) { File.join(reader_cache_root, 'deadbeef') }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    FileUtils.mkdir_p(File.join(book_dir, 'META-INF'))
    # Minimal manifest and files
    File.write(File.join(book_dir, 'manifest.json'), JSON.generate({
      'title' => 'Cached Book',
      'author' => 'A. Author',
      'authors' => ['A. Author'],
      'opf_path' => 'OEBPS/content.opf',
      'spine' => ['OEBPS/ch1.xhtml']
    }))
    FileUtils.mkdir_p(File.join(book_dir, 'OEBPS'))
    File.write(File.join(book_dir, 'META-INF', 'container.xml'), '<c/>')
    File.write(File.join(book_dir, 'OEBPS', 'content.opf'), '<opf/>')
    File.write(File.join(book_dir, 'OEBPS', 'ch1.xhtml'), '<html><body><p>Hello</p></body></html>')
  end

  it 'opens instantly from Library by using cache directory' do
    # Stub MouseableReader to capture open path without launching terminal
    reader = class_double('EbookReader::MouseableReader').as_stubbed_const
    expect(reader).to receive(:new).with(book_dir, anything, anything).and_return(double(run: true))

    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)
    # Call selection directly to avoid terminal dispatcher differences in test env
    mm.library_select
  end
end
