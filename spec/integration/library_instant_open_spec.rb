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

    doc = Struct.new(:cache_path, :canonical_path).new(cache.cache_path, epub_path)
    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :split, :normal)
    pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 1, 'start_line' => 0, 'end_line' => 0 },
    ]
    EbookReader::Infrastructure::PaginationCache.save_for_document(doc, key, pages)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'opens instantly from Library by using cache directory' do
    # Stub MouseableReader to capture open path without launching terminal
    captured_container = nil
    reader = class_double('EbookReader::MouseableReader').as_stubbed_const
    expect(reader).to receive(:new) do |_path, _unused, container|
      captured_container = container
      instance_double('MouseableReader', run: true)
    end

    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)
    mm.state.update({ %i[config view_mode] => :split,
                      %i[config line_spacing] => :normal,
                      %i[config page_numbering_mode] => :dynamic })
    # Call selection directly to avoid terminal dispatcher differences in test env
    mm.library_select

    expect(captured_container).not_to be_nil
    calculator = captured_container.resolve(:page_calculator)
    state = captured_container.resolve(:global_state)
    doc = captured_container.resolve(:document)
    preloader = EbookReader::Application::PaginationCachePreloader.new(
      state: state,
      page_calculator: calculator,
      pagination_cache: captured_container.resolve(:pagination_cache)
    )
    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :split, :normal)
    expect(EbookReader::Infrastructure::PaginationCache.load_for_document(doc, key)).not_to be_nil
    result = preloader.preload(doc, width: 80, height: 24)
    expect(result.status).to eq(:hit)
    expect(calculator.total_pages).to be_positive
  end
end
