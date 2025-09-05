# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::ReaderController do
  before do
    mock_terminal(width: 80, height: 24)

    # Stub DocumentService to provide content
    stub_const('EbookReader::Infrastructure::DocumentService', Class.new do
      FakeChapter = Struct.new(:title, :lines)
      class FakeDoc
        def initialize(ch) = (@ch = ch)
        def chapter_count = 1
        def chapters = [@ch]
        def get_chapter(_i) = @ch
        def title = 'Doc'
        def language = 'en'
      end

      def initialize(_path); end

      def load_document
        lines = Array.new(100) { |i| "Line #{i}" }
        FakeDoc.new(FakeChapter.new('Ch', lines))
      end
    end)
  end

  it 'rebuilds dynamic page map on resize' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    page_calc = instance_double('PageCalculator', build_page_map: nil, total_pages: 10,
                                              get_page: { lines: Array.new(10, 'x'), start_line: 0, chapter_index: 0 })
    container.register(:page_calculator, page_calc)

    # Set dynamic mode
    state = container.resolve(:global_state)
    state.update({ %i[config page_numbering_mode] => :dynamic })

    ctrl = described_class.new('/tmp/fake.epub', nil, container)
    # Initial draw to set baseline
    ctrl.draw_screen

    # Change terminal size to trigger size_changed?
    allow(EbookReader::Terminal).to receive(:size).and_return([30, 100])

    expect(page_calc).to receive(:build_page_map).at_least(:once)
    ctrl.draw_screen
  end
end
