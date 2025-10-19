# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/helpers/text_metrics'
require 'ebook_reader/infrastructure/parsers/xhtml_content_parser'

RSpec.describe EbookReader::Components::Reading::SingleViewRenderer do
  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) do
    store = EbookReader::Infrastructure::ObserverStateStore.new(event_bus)
    store.update(
      [%i[reader current_chapter] => 0,
       %i[reader single_page] => 0,
       %i[reader current_page] => 1,
       %i[reader current_page_index] => 0,
       %i[reader mode] => :read,
       %i[config view_mode] => :single,
       %i[config line_spacing] => :normal,
       %i[config page_numbering_mode] => :absolute,
       %i[config show_page_numbers] => true]
    )
    store
  end

  let(:layout_service) do
    Class.new do
      def calculate_metrics(width, height, _mode)
        [width - 6, height - 4]
      end

      def adjust_for_line_spacing(height, _spacing)
        height
      end

      def calculate_center_start_row(content_height, lines_count, _line_spacing)
        [((content_height - lines_count) / 2.0).floor, 1].max
      end
    end.new
  end

  let(:html_content) do
    <<~HTML
      <html><body>
        <h1>Formatter Demo</h1>
        <p>Paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
        <ul><li>First bullet</li><li>Second bullet</li></ul>
        <pre><code>code line 1\ncode line 2</code></pre>
      </body></html>
    HTML
  end

  let(:chapter) do
    EbookReader::Domain::Models::Chapter.new(
      number: '1',
      title: 'Demo',
      lines: nil,
      metadata: nil,
      blocks: nil,
      raw_content: html_content
    )
  end

  let(:document) do
    Class.new do
      def initialize(chapter)
        @chapter = chapter
      end

      def canonical_path = '/tmp/demo.epub'
      def chapter_count = 1
      def chapters = [@chapter]
      def get_chapter(_index) = @chapter
      def title = 'Demo Title'
    end.new(chapter)
  end

  let(:formatting_dependencies) do
    instance_double(EbookReader::Domain::DependencyContainer).tap do |deps|
      parser_factory = lambda do |raw|
        EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(raw)
      end
      allow(deps).to receive(:resolve).with(:xhtml_parser_factory).and_return(parser_factory)
      allow(deps).to receive(:resolve).with(:logger).and_return(nil)
    end
  end
  let(:formatting_service) { EbookReader::Domain::Services::FormattingService.new(formatting_dependencies) }

  let(:deps) do
    container = EbookReader::Domain::DependencyContainer.new
    container.register(:layout_service, layout_service)
    container.register(:global_state, state)
    container.register(:formatting_service, formatting_service)
    container.register(:document, document)
    container
  end

  class CapturingOutput
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(row, col, text)
      @writes << [row, col, text]
    end
  end

  it 'renders headings, list markers, and code blocks with formatting cues' do
    deps.resolve(:global_state).update({ %i[config highlight_quotes] => true })

    renderer = described_class.new(deps)
    output = CapturingOutput.new
    surface = EbookReader::Components::Surface.new(output)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)

    renderer.render(surface, bounds)

    writes = output.writes

    heading_write = writes.find { |(_, _, text)| text.include?('Formatter Demo') }
    expect(heading_write).not_to be_nil
    expect(heading_write[2]).to include(EbookReader::Components::RenderStyle.color(:heading))

    bullet_write = writes.find { |(_, _, text)| text.include?('First bullet') }
    expect(bullet_write).not_to be_nil
    bullet_plain = bullet_write[2].gsub(EbookReader::Helpers::TextMetrics::ANSI_REGEX, '')
    expect(bullet_plain).to start_with('• First bullet')

    code_write = writes.find { |(_, _, text)| text.include?('code line 1') }
    expect(code_write).not_to be_nil
    expect(code_write[2]).to include(EbookReader::Terminal::ANSI::YELLOW)
  end
end
