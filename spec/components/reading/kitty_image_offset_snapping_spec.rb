# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Kitty image offset snapping' do
  class FakeKittyImageRenderer
    attr_reader :calls

    def initialize
      @calls = []
    end

    def enabled?(_config_store)
      true
    end

    def prepare_virtual(**kwargs)
      @calls << kwargs
      42
    end
  end

  class DemoDoc
    def initialize(chapter)
      @chapter = chapter
    end

    def canonical_path = '/tmp/demo.epub'
    def cache_sha = 'a' * 64
    def title = 'Demo'
    def chapter_count = 1
    def get_chapter(_index) = @chapter
  end

  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) do
    store = EbookReader::Infrastructure::ObserverStateStore.new(event_bus)
    store.update({
                   %i[reader current_chapter] => 0,
                   %i[reader single_page] => 0,
                   %i[reader current_page] => 0,
                   %i[reader mode] => :read,
                   %i[config view_mode] => :single,
                   %i[config line_spacing] => :normal,
                   %i[config page_numbering_mode] => :absolute,
                   %i[config show_page_numbers] => false,
                   %i[config kitty_images] => true,
                 })
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
        <p>Above</p>
        <img src="img1.jpg" alt="One" />
        <p>Below</p>
      </body></html>
    HTML
  end

  let(:chapter) do
    EbookReader::Domain::Models::Chapter.new(
      number: '1',
      title: 'Demo',
      lines: nil,
      metadata: { source_path: 'OEBPS/ch1.xhtml' },
      blocks: nil,
      raw_content: html_content
    )
  end

  let(:document) { DemoDoc.new(chapter) }

  let(:deps) do
    container = EbookReader::Domain::DependencyContainer.new
    container.register(:layout_service, layout_service)
    container.register(:global_state, state)
    container.register(
      :xhtml_parser_factory,
      lambda do |raw|
        EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(raw)
      end
    )
    container.register(:logger, nil)
    container.register(:document, document)

    formatting_service = EbookReader::Domain::Services::FormattingService.new(container)
    container.register(:formatting_service, formatting_service)

    fake_kitty = FakeKittyImageRenderer.new
    container.register(:kitty_image_renderer, fake_kitty)
    container
  end

  before do
    allow(EbookReader::Infrastructure::KittyGraphics).to receive(:supported?).and_return(true)
    EbookReader::TestSupport::TerminalDouble.reset!
  end

  it 'renders the image even when the page offset lands inside the image block' do
    renderer = EbookReader::Components::Reading::SingleViewRenderer.new(deps)
    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 22, height: 16)

    col_width, content_height = layout_service.calculate_metrics(bounds.width, bounds.height, :single)
    lines_per_page = layout_service.adjust_for_line_spacing(content_height, :normal)
    wrapped = deps.resolve(:formatting_service).wrap_all(document, 0, col_width, config: state, lines_per_page: lines_per_page)
    spacer_index = wrapped.find_index { |line| line.respond_to?(:metadata) && line.metadata.is_a?(Hash) && line.metadata[:image_spacer] }
    expect(spacer_index).not_to be_nil

    state.update({ %i[reader single_page] => spacer_index })

    renderer.render(surface, bounds)

    placeholder_char = EbookReader::Helpers::KittyUnicodePlaceholders::PLACEHOLDER_CHAR
    kitty_writes = EbookReader::TestSupport::TerminalDouble.writes.select { |w| w[:text].include?(placeholder_char) }
    expect(kitty_writes).not_to be_empty

    fake_kitty = deps.resolve(:kitty_image_renderer)
    expect(fake_kitty.calls.length).to eq(1)
  end

  it 'prepares kitty images for every render frame' do
    renderer = EbookReader::Components::Reading::SingleViewRenderer.new(deps)
    surface = EbookReader::Components::Surface.new(EbookReader::TestSupport::TerminalDouble)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 22, height: 16)

    renderer.render(surface, bounds)
    renderer.render(surface, bounds)

    fake_kitty = deps.resolve(:kitty_image_renderer)
    expect(fake_kitty.calls.length).to eq(2)
  end
end
