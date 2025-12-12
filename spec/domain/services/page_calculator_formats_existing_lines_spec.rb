# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  class PCFEL_FakeChapter
    attr_reader :lines

    def initialize(lines)
      @lines = lines
    end
  end

  class PCFEL_FakeDoc
    attr_reader :chapters

    def initialize(chapters)
      @chapters = chapters
    end

    def chapter_count = chapters.length
    def get_chapter(idx) = chapters[idx]
  end

  it 'rehydrates plain page lines with formatting when available' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)
    state.update({ %i[config page_numbering_mode] => :dynamic,
                   %i[config view_mode] => :single,
                   %i[config line_spacing] => :compact,
                   %i[ui terminal_width] => 40,
                   %i[ui terminal_height] => 10 })

    formatted_line = EbookReader::Domain::Models::DisplayLine.new(
      text: 'fmt',
      segments: [EbookReader::Domain::Models::TextSegment.new(text: 'fmt', styles: { bold: true })],
      metadata: { block_type: :heading }
    )
    formatting = instance_double(EbookReader::Domain::Services::FormattingService)
    allow(formatting).to receive(:wrap_window).and_return([formatted_line])
    container.register(:formatting_service, formatting)

    doc = PCFEL_FakeDoc.new([PCFEL_FakeChapter.new(['raw one', 'raw two', 'raw three'])])
    container.register(:document, doc)
    calculator = described_class.new(container)

    # Force a page with pre-populated plain strings (simulating an older cache/build)
    calculator.instance_variable_set(:@pages_data, [
      { chapter_index: 0, page_in_chapter: 0, total_pages_in_chapter: 1,
        start_line: 0, end_line: 2, lines: ['raw one', 'raw two', 'raw three'] }
    ])

    page = calculator.get_page(0)
    expect(page[:lines].first).to respond_to(:segments)
  end
end
