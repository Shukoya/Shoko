# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  include FakeFS::SpecHelpers

  # Minimal fake chapter and document
  class PCP_FakeChapter
    attr_reader :lines
    def initialize(lines)
      @lines = lines
    end
  end

  class PCP_FakeDoc
    attr_reader :cache_dir
    def initialize(cache_dir, chapters)
      @cache_dir = cache_dir
      @chapters = chapters
    end
    def chapter_count
      @chapters.length
    end
    def get_chapter(idx)
      @chapters[idx]
    end
  end

  let(:home) { '/home/test' }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:book_dir) { File.join(reader_root, 'deadbeef') }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    FileUtils.mkdir_p(book_dir)
  end

  it 'loads pagination from cache for matching layout and returns totals and pages immediately' do
    # Build fake document with simple short lines to avoid wrapping changes
    lines = Array.new(100) { |i| "L#{i}" } # each short -> no additional wrapping
    doc = PCP_FakeDoc.new(book_dir, [PCP_FakeChapter.new(lines)])

    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal)
    compact_pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 4, 'start_line' => 0, 'end_line' => 24 },
      { 'chapter_index' => 0, 'page_in_chapter' => 1, 'total_pages_in_chapter' => 4, 'start_line' => 25, 'end_line' => 49 },
      { 'chapter_index' => 0, 'page_in_chapter' => 2, 'total_pages_in_chapter' => 4, 'start_line' => 50, 'end_line' => 74 },
      { 'chapter_index' => 0, 'page_in_chapter' => 3, 'total_pages_in_chapter' => 4, 'start_line' => 75, 'end_line' => 99 },
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
    expect(service.total_pages).to eq(4)

    # get_page should populate lines lazily based on start/end line using wrap_window
    p0 = service.get_page(1)
    expect(p0[:lines]).to be_a(Array)
    expect(p0[:lines].length).to eq(25)
    expect(p0[:lines].first).to eq('L25')
  end
end
