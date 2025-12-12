# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  let(:tmp_dir) { Dir.mktmpdir }

  # Minimal fake chapter and document
  class PCP_FakeChapter
    attr_reader :lines

    def initialize(lines)
      @lines = lines
    end
  end

  class PCP_FakeDoc
    attr_reader :cache_path, :canonical_path

    def initialize(cache_path, chapters, canonical_path = nil)
      @cache_path = cache_path
      @canonical_path = canonical_path
      @chapters = chapters
    end

    def chapter_count
      @chapters.length
    end

    def get_chapter(idx)
      @chapters[idx]
    end
  end

  let(:home) { tmp_dir }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:epub_path) { File.join(home, 'books/demo.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }

  before do
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub-data')
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Demo',
      language: 'en_US',
      authors: ['Author'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Demo', lines: Array.new(100) { |i| "L#{i}" }, metadata: nil, blocks: nil, raw_content: '<p></p>')],
      toc_entries: [],
      opf_path: 'OPS/content.opf',
      spine: ['xhtml/1.xhtml'],
      chapter_hrefs: ['xhtml/1.xhtml'],
      resources: { 'META-INF/container.xml' => '<xml/>' },
      metadata: {},
      container_path: 'META-INF/container.xml',
      container_xml: '<xml/>'
    )
    cache.write_book!(book)
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'loads pagination from cache for matching layout and returns totals and pages immediately' do
    # Build fake document with simple short lines to avoid wrapping changes
    lines = Array.new(100) { |i| "L#{i}" } # each short -> no additional wrapping
    doc = PCP_FakeDoc.new(cache.cache_path, [PCP_FakeChapter.new(lines)], epub_path)

    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal)
    compact_pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 7, 'start_line' => 0, 'end_line' => 14 },
      { 'chapter_index' => 0, 'page_in_chapter' => 1, 'total_pages_in_chapter' => 7, 'start_line' => 15, 'end_line' => 29 },
      { 'chapter_index' => 0, 'page_in_chapter' => 2, 'total_pages_in_chapter' => 7, 'start_line' => 30, 'end_line' => 44 },
      { 'chapter_index' => 0, 'page_in_chapter' => 3, 'total_pages_in_chapter' => 7, 'start_line' => 45, 'end_line' => 59 },
      { 'chapter_index' => 0, 'page_in_chapter' => 4, 'total_pages_in_chapter' => 7, 'start_line' => 60, 'end_line' => 74 },
      { 'chapter_index' => 0, 'page_in_chapter' => 5, 'total_pages_in_chapter' => 7, 'start_line' => 75, 'end_line' => 89 },
      { 'chapter_index' => 0, 'page_in_chapter' => 6, 'total_pages_in_chapter' => 7, 'start_line' => 90, 'end_line' => 99 },
    ]
    ok = EbookReader::Infrastructure::PaginationCache.save_for_document(doc, key, compact_pages)
    expect(ok).to be true

    # Container and state
    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)
    # Configure state to dynamic numbering and layout
    state.update({ %i[config page_numbering_mode] => :dynamic,
                   %i[config line_spacing] => :normal,
                   %i[reader view_mode] => :single,
                   %i[ui terminal_width] => 80,
                   %i[ui terminal_height] => 24 })

    # Provide document to DI so get_page can lazy load lines
    container.register(:document, doc)

    service = described_class.new(container)

    pages = service.build_page_map(80, 24, doc, state)
    expect(pages).to be_a(Array)
    expect(service.total_pages).to eq(7)

    # get_page should populate lines lazily based on start/end line using wrap_window
    p0 = service.get_page(1)
    expect(p0[:lines]).to be_a(Array)
    expect(p0[:lines].length).to eq(15)
    expect(p0[:lines].first).to eq('L15')
  end
end
