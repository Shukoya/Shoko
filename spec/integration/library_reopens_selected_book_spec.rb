# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library reopening cached books respects selection' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:home) { tmp_dir }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:book_a_epub) { File.join(home, 'book_a.epub') }
  let(:book_b_epub) { File.join(home, 'book_b.epub') }

  before do
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(reader_cache_root)
    FileUtils.mkdir_p(reader_cache_root)

    @book_a_cache = build_cached_book(book_a_epub, title: 'Cached One', author: 'Author A')
    @book_b_cache = build_cached_book(book_b_epub, title: 'Cached Two', author: 'Author B')

    allow(EbookReader::RecentFiles).to receive(:add)
    allow(EbookReader::RecentFiles).to receive(:load).and_return([])
    allow(EbookReader::RecentFiles).to receive(:clear)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'opens the newly selected book after quitting the first reader session' do
    menu = EbookReader::MainMenu.new
    menu.switch_to_mode(:library)

    terminal = menu.terminal_service
    terminal.queue_input('q')
    menu.library_select

    menu.library_down
    terminal.queue_input('q')
    menu.library_select

    document = menu.dependencies.resolve(:document)
    expect(document).to respond_to(:canonical_path)
    expect(document.canonical_path).to eq(book_b_epub)
  end

  def build_cached_book(epub_path, title:, author:)
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub payload')

    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: title,
      language: 'en_US',
      authors: [author],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title:, lines: ['Hi'], metadata: nil, blocks: nil, raw_content: '<p>Hi</p>')],
      toc_entries: [],
      opf_path: 'OEBPS/content.opf',
      spine: ['OEBPS/ch1.xhtml'],
      chapter_hrefs: ['OEBPS/ch1.xhtml'],
      resources: {
        'META-INF/container.xml' => '<c/>',
        'OEBPS/content.opf' => '<opf/>',
        'OEBPS/ch1.xhtml' => '<html><body><p>Hi</p></body></html>',
      },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<c/>'
    )
    cache = EbookReader::Infrastructure::EpubCache.new(epub_path)
    cache.write_book!(book)
    cache
  end
end
