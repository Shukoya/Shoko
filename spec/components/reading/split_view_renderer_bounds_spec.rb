# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Reading::SplitViewRenderer do
  class SplitBoundsChapter
    attr_reader :lines, :title

    def initialize(lines)
      @lines = lines
      @title = 'Bounds Fixture'
    end
  end

  class SplitBoundsDoc
    def initialize(lines)
      @chapter = SplitBoundsChapter.new(lines)
    end

    def get_chapter(_idx)
      @chapter
    end
  end

  class CaptureOutput
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(row, col, text)
      @writes << { row: row.to_i, col: col.to_i, text: text.to_s }
    end
  end

  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state) { container.resolve(:global_state) }

  before do
    container.register(:document, SplitBoundsDoc.new(['hello world']))
    state.update(
      {
        %i[config view_mode] => :split,
        %i[config page_numbering_mode] => :absolute,
        %i[reader current_chapter] => 0,
        %i[reader left_page] => 0,
        %i[reader right_page] => 10,
      }
    )
  end

  it 'renders using coordinates relative to the provided bounds' do
    renderer = described_class.new(container)
    capture = CaptureOutput.new
    surface = EbookReader::Components::Surface.new(capture)

    bounds = EbookReader::Components::Rect.new(x: 20, y: 5, width: 80, height: 24)
    renderer.render(surface, bounds)

    expect(capture.writes).not_to be_empty

    expected_left_margin_col = bounds.x + EbookReader::Domain::Services::LayoutService::SPLIT_LEFT_MARGIN
    wrote_at_expected_margin = capture.writes.any? { |w| w[:col] == expected_left_margin_col }
    expect(wrote_at_expected_margin).to be(true)
  end
end
