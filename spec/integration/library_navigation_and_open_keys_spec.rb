# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library navigation and open via keys' do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:home) { tmp_dir }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:book1_epub) { File.join(home, 'books', 'book1.epub') }
  let(:book2_epub) { File.join(home, 'books', 'book2.epub') }

  before do
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(reader_cache_root)
    FileUtils.mkdir_p(File.dirname(book1_epub))
    File.write(book1_epub, 'book1')
    File.write(book2_epub, 'book2')

    @book1_cache = build_cache(book1_epub, title: 'Cached One', author: 'Author A', body: 'Hi')
    @book2_cache = build_cache(book2_epub, title: 'Cached Two', author: 'Author B', body: 'Yo')
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'navigates with arrow keys and opens selected with Enter' do
    # Stub MouseableReader to capture open path without launching terminal
    reader = class_double('EbookReader::MouseableReader').as_stubbed_const

    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)
    expect(mm.main_menu_component.current_screen.items.length).to eq(2)
    items = mm.main_menu_component.current_screen.items
    target_path = items[1][:open_path]
    expect(reader).to receive(:new).with(target_path, anything, anything).and_return(double(run: true))
    dispatcher = mm.instance_variable_get(:@dispatcher)

    # Down (vi key) to second item
    dispatcher.handle_key('j')
    # Enter to open
    dispatcher.handle_key("\r")
  end

  it 'moves selection up and down within bounds' do
    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)

    state = mm.state
    dispatcher = mm.instance_variable_get(:@dispatcher)

    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Sanity: direct call updates selection
    mm.library_down
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(1)
    mm.library_up
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Move down to 1 (vi key)
    dispatcher.handle_key('j')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(1)

    # Move up back to 0 (vi key)
    dispatcher.handle_key('k')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Move up stays at 0 (no negative)
    dispatcher.handle_key('k')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)
  end

  def build_cache(epub_path, title:, author:, body:)
    cache = EbookReader::Infrastructure::EpubCache.new(epub_path)
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: title,
      language: 'en_US',
      authors: [author],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: title, lines: [body], metadata: nil, blocks: nil, raw_content: "<p>#{body}</p>")],
      toc_entries: [],
      opf_path: 'OEBPS/content.opf',
      spine: ['OEBPS/ch1.xhtml'],
      chapter_hrefs: ['OEBPS/ch1.xhtml'],
      resources: {
        'META-INF/container.xml' => '<c/>',
        'OEBPS/content.opf' => '<opf/>',
        'OEBPS/ch1.xhtml' => "<html><body><p>#{body}</p></body></html>",
      },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<c/>'
    )
    cache.write_book!(book)
    cache
  end
end
