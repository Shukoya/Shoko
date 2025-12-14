# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Render geometry tab alignment' do
  class TabFixtureDoc
    def initialize(raw_html)
      @chapter = EbookReader::Domain::Models::Chapter.new(
        number: '1',
        title: 'Fixture',
        lines: nil,
        metadata: nil,
        blocks: nil,
        raw_content: raw_html
      )
    end

    def chapter_count = 1

    def get_chapter(_idx) = @chapter

    def canonical_path = '/tmp/tab-fixture.epub'
  end

  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state) { container.resolve(:global_state) }
  let(:render_registry) { container.resolve(:render_registry) }

  before do
    raw = <<~HTML
      <html><body><pre><code>a\tb</code></pre></body></html>
    HTML
    container.register(:document, TabFixtureDoc.new(raw))
    state.update(
      %i[config view_mode] => :single,
      %i[config page_numbering_mode] => :absolute,
      %i[reader current_chapter] => 0,
      %i[reader single_page] => 0,
      %i[reader current_page_index] => 0
    )
  end

  it 'records geometry that matches tab expansion at the render column' do
    renderer = EbookReader::Components::Reading::SingleViewRenderer.new(container)
    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 20)

    EbookReader::TestSupport::TerminalDouble.reset!
    renderer.render(surface, bounds)

    geometries = render_registry.lines.values.map { |entry| entry[:geometry] }.compact
    geometry = geometries.find { |g| g.plain_text.include?('a') && g.plain_text.include?('b') }

    expect(geometry).not_to be_nil
    expect(geometry.plain_text).not_to include("\t")

    start_column = geometry.column_origin - 1
    expected = EbookReader::Helpers::TextMetrics.truncate_to("a\tb", 200, start_column: start_column)
    expect(geometry.plain_text).to eq(expected)
    expect(geometry.visible_width).to eq(EbookReader::Helpers::TextMetrics.visible_length(expected))
  end
end

