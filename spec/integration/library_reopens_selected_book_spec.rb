# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library reopening cached books respects selection', :fakefs do
  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:book_a_dir) { File.join(reader_cache_root, 'booksha1') }
  let(:book_b_dir) { File.join(reader_cache_root, 'booksha2') }
  let(:book_a_epub) { File.join(home, 'book_a.epub') }
  let(:book_b_epub) { File.join(home, 'book_b.epub') }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    FileUtils.mkdir_p(reader_cache_root)

    build_cached_book(book_a_dir, book_a_epub, title: 'Cached One', author: 'Author A')
    build_cached_book(book_b_dir, book_b_epub, title: 'Cached Two', author: 'Author B')

    allow(EbookReader::RecentFiles).to receive(:add)
    allow(EbookReader::RecentFiles).to receive(:load).and_return([])
    allow(EbookReader::RecentFiles).to receive(:clear)
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

  def build_cached_book(dir, epub_path, title:, author:)
    FileUtils.mkdir_p(File.join(dir, 'META-INF'))
    FileUtils.mkdir_p(File.join(dir, 'OEBPS'))

    manifest = {
      'title' => title,
      'author' => author,
      'authors' => [author],
      'opf_path' => 'OEBPS/content.opf',
      'spine' => ['OEBPS/ch1.xhtml'],
      'epub_path' => epub_path,
    }
    File.write(File.join(dir, 'manifest.json'), JSON.generate(manifest))
    File.write(File.join(dir, 'META-INF', 'container.xml'), '<c/>')
    File.write(File.join(dir, 'OEBPS', 'content.opf'), '<opf/>')
    File.write(File.join(dir, 'OEBPS', 'ch1.xhtml'), '<html><body><p>Hi</p></body></html>')
    File.write(epub_path, 'epub payload')
  end
end
