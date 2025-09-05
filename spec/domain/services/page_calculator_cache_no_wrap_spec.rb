# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  include FakeFS::SpecHelpers

  class PCCN_FakeChapter
    attr_reader :lines
    def initialize(lines)
      @lines = lines
    end
  end

  class PCCN_FakeDoc
    attr_reader :cache_dir
    def initialize(cache_dir, chapters)
      @cache_dir = cache_dir
      @chapters = chapters
    end
    def chapter_count = @chapters.length
    def get_chapter(idx) = @chapters[idx]
  end

  let(:home) { '/home/test' }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:book_dir) { File.join(reader_root, 'deadbeef') }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    FileUtils.mkdir_p(File.join(book_dir, 'pagination'))
  end

  it 'does not invoke wrapping service during build when cached pagination exists' do
    # Prepare compact cached pagination file
    key = EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal)
    compact_pages = [
      { 'chapter_index' => 0, 'page_in_chapter' => 0, 'total_pages_in_chapter' => 1, 'start_line' => 0, 'end_line' => 9 },
    ]
    ok = EbookReader::Infrastructure::PaginationCache.save_for_document(PCCN_FakeDoc.new(book_dir, []), key, compact_pages)
    expect(ok).to be true

    # Doc and container
    lines = Array.new(10) { |i| "L#{i}" }
    doc = PCCN_FakeDoc.new(book_dir, [PCCN_FakeChapter.new(lines)])
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
