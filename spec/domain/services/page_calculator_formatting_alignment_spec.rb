# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::PageCalculatorService do
  class PCFA_FakeChapter
    attr_accessor :lines

    def initialize(lines)
      @lines = lines
    end
  end

  class PCFA_FakeDoc
    attr_reader :chapters

    def initialize(chapters)
      @chapters = chapters
    end

    def chapter_count = chapters.length
    def get_chapter(idx) = chapters[idx]
  end

  it 'builds dynamic pagination using formatting/wrapping output so pages align with rendering' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)
    state.update({ %i[config page_numbering_mode] => :dynamic,
                   %i[config view_mode] => :single,
                   %i[config line_spacing] => :compact,
                   %i[ui terminal_width] => 40,
                   %i[ui terminal_height] => 6 })

    formatting = instance_double(EbookReader::Domain::Services::FormattingService)
    allow(formatting).to receive(:wrap_all).and_return(Array.new(5) { |i| "F#{i}" })
    container.register(:formatting_service, formatting)

    doc = PCFA_FakeDoc.new([PCFA_FakeChapter.new(['raw one', 'raw two'])])
    calculator = described_class.new(container)

    calculator.build_page_map(40, 6, doc, state)

    expect(formatting).to have_received(:wrap_all).at_least(:once)
    expect(calculator.total_pages).to eq(2) # 5 formatted lines over 3-lines-per-page -> 2 pages, not 1
  end
end
