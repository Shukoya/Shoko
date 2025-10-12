# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library instant open' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:home) { tmp_dir }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:epub_path) { File.join(home, 'books', 'cached.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }

  before do
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(reader_cache_root)
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'book')
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Cached Book',
      language: 'en_US',
      authors: ['A. Author'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Cached Book', lines: ['Hello'], metadata: nil, blocks: nil, raw_content: '<p>Hello</p>')],
      toc_entries: [],
      opf_path: 'OEBPS/content.opf',
      spine: ['OEBPS/ch1.xhtml'],
      chapter_hrefs: ['OEBPS/ch1.xhtml'],
      resources: {
        'META-INF/container.xml' => '<c/>',
        'OEBPS/content.opf' => '<opf/>',
        'OEBPS/ch1.xhtml' => '<html><body><p>Hello</p></body></html>',
      },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<c/>'
    )
    cache.write_book!(book)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'opens instantly from Library by using cache directory' do
    # Stub MouseableReader to capture open path without launching terminal
    reader = class_double('EbookReader::MouseableReader').as_stubbed_const
    expect(reader).to receive(:new).with(cache.cache_path, anything, anything).and_return(double(run: true))

    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)
    # Call selection directly to avoid terminal dispatcher differences in test env
    mm.library_select
  end
end
