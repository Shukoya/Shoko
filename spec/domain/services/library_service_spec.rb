# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::LibraryService do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_root) { File.join(xdg_cache, 'reader') }
  let(:epub_path) { File.join(home, 'books', 'library.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }

  let(:recent_repository) do
    Class.new do
      def initialize(items)
        @items = items
      end

      def all
        @items
      end
    end.new([
              { 'path' => '/tmp/book.epub', 'accessed' => '2020-01-01T00:00:00Z' },
            ])
  end

  let(:dependencies) do
    container = EbookReader::Domain::DependencyContainer.new
    container.register(
      :cached_library_repository,
      EbookReader::Infrastructure::Repositories::CachedLibraryRepository.new(cache_root: reader_root)
    )
    container.register(:recent_library_repository, recent_repository)
    container
  end

  subject(:service) { described_class.new(dependencies) }

  before do
    @old_home = ENV['HOME']
    @old_cache = ENV['XDG_CACHE_HOME']
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(reader_root)
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub')
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Test Book',
      language: 'en_US',
      authors: ['Tester'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Test Book', lines: ['Hi'], metadata: nil, blocks: nil, raw_content: '<p>Hi</p>')],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['OPS/ch1.xhtml'],
      chapter_hrefs: ['OPS/ch1.xhtml'],
      resources: {
        'META-INF/container.xml' => '<xml/>',
        'OPS/content.opf' => '<xml/>',
        'OPS/ch1.xhtml' => '<html><body><p>Hi</p></body></html>',
      },
      metadata: { year: '2022' },
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )
    cache.write_book!(book)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
  end

  it 'lists cached books with basic metadata' do
    items = service.list_cached_books
    expect(items.length).to eq(1)
    book = items.first
    expect(book[:title]).to eq('Test Book')
    expect(book[:authors]).to eq('Tester')
    expect(book[:open_path]).to eq(cache.cache_path)
    expect(book[:epub_path]).to eq(epub_path)
    expect(book[:year]).to eq('2022')
  end
end
