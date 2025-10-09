# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Render geometry integration' do
  class GeometryFixtureChapter
    attr_reader :lines, :title

    def initialize(lines)
      @lines = lines
      @title = 'Fixture'
    end
  end

  class GeometryFixtureDoc
    def initialize(lines)
      @chapter = GeometryFixtureChapter.new(lines)
    end

    def chapter_count = 1

    def get_chapter(_idx)
      @chapter
    end
  end

  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state) { container.resolve(:global_state) }

  before do
    doc = GeometryFixtureDoc.new([
      "漢字	mix",
      'plain text line',
    ])
    container.register(:document, doc)
    state.update({ %i[config view_mode] => :single,
                   %i[config page_numbering_mode] => :absolute,
                   %i[reader current_chapter] => 0,
                   %i[reader single_page] => 0 })
  end

  it 'stores geometry with correct cell widths after render' do
    renderer = EbookReader::Components::Reading::SingleViewRenderer.new(container)
    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)

    EbookReader::TestSupport::TerminalDouble.reset!
    renderer.render(surface, bounds)

    rendered = state.get(%i[reader rendered_lines])
    expect(rendered).not_to be_empty

    geometry = rendered.values.first[:geometry]
    expect(geometry).to be_a(EbookReader::Models::LineGeometry)
    expect(geometry.visible_width).to eq(EbookReader::Helpers::TextMetrics.visible_length(geometry.plain_text))
  end
end
