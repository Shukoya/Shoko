# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  let(:tmp_dir) { Dir.mktmpdir }

  class PCCN_FakeChapter
    attr_reader :lines

    def initialize(lines)
      @lines = lines
    end
  end

  class PCCN_FakeDoc
    attr_reader :cache_path, :canonical_path

    def initialize(cache_path, chapters, canonical_path = nil)
      @cache_path = cache_path
      @canonical_path = canonical_path
      @chapters = chapters
    end

    def chapter_count = @chapters.length
    def get_chapter(idx) = @chapters[idx]
  end

  let(:home) { tmp_dir }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:epub_path) { File.join(home, 'books/demo.epub') }
  let(:cache) { EbookReader::Infrastructure::EpubCache.new(epub_path) }

  before do
    @old_home = ENV['HOME']
    @old_cache = ENV['XDG_CACHE_HOME']
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    FileUtils.mkdir_p(File.dirname(epub_path))
    File.write(epub_path, 'epub-data')
    book = EbookReader::Infrastructure::EpubCache::BookData.new(
      title: 'Demo',
      language: 'en_US',
      authors: ['Author'],
      chapters: [EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Demo', lines: Array.new(10) { |i| "L#{i}" }, metadata: nil, blocks: nil, raw_content: '<p></p>')],
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

  it 'does not invoke wrapping service during build when cached pagination exists' do
    # Prepare compact cached pagination file
    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal)
    compact_pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 1, 'start_line' => 0, 'end_line' => 9 },
    ]
    ok = EbookReader::Infrastructure::PaginationCache.save_for_document(PCCN_FakeDoc.new(cache.cache_path, [], epub_path), key, compact_pages)
    expect(ok).to be true

    # Doc and container
    lines = Array.new(10) { |i| "L#{i}" }
    doc = PCCN_FakeDoc.new(cache.cache_path, [PCCN_FakeChapter.new(lines)], epub_path)
    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)
    state.update({ %i[config page_numbering_mode] => :dynamic,
                   %i[config line_spacing] => :normal,
                   %i[reader view_mode] => :single })

    # WrappingService double should not be called during build_page_map when cached exists
    wrapper = instance_double(EbookReader::Domain::Services::WrappingService)
    allow(wrapper).to receive(:wrap_window) { raise 'wrap_window should not be called during build' }
    allow(wrapper).to receive(:wrap_lines) { raise 'wrap_lines should not be called during build' }
    container.register(:wrapping_service, wrapper)

    service = described_class.new(container)
    # Should load cached data without touching wrapping service
    expect { service.build_page_map(80, 24, doc, state) }.not_to raise_error
    expect(service.total_pages).to eq(1)
  end
end
