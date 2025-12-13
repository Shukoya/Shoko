# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::NavigationService do
  it 'snaps absolute page offsets to the start of an image block in kitty mode' do
    allow(EbookReader::Infrastructure::KittyGraphics).to receive(:supported?).and_return(true)

    state_store = EbookReader::Infrastructure::StateStore.new
    state_store.update({
                         %i[config page_numbering_mode] => :absolute,
                         %i[config view_mode] => :single,
                         %i[config kitty_images] => true,
                         %i[ui terminal_width] => 80,
                         %i[ui terminal_height] => 24,
                         %i[reader total_chapters] => 1,
                         %i[reader current_chapter] => 0,
                         %i[reader single_page] => 0,
                         %i[reader current_page] => 0,
                         %i[reader page_map] => [10],
                       })

    layout_service = instance_double(EbookReader::Domain::Services::LayoutService)
    allow(layout_service).to receive(:calculate_metrics).with(80, 24, :single).and_return([50, 10])
    allow(layout_service).to receive(:calculate_metrics).with(80, 24, :split).and_return([40, 10])
    allow(layout_service).to receive(:adjust_for_line_spacing).and_return(10)

    html = <<~HTML
      <html><body>
        <p>Intro</p>
        <img src="img1.jpg" alt="One" />
        <p>After</p>
      </body></html>
    HTML

    chapter = EbookReader::Domain::Models::Chapter.new(
      number: '1',
      title: 'Demo',
      lines: nil,
      metadata: { source_path: 'OEBPS/ch1.xhtml' },
      blocks: nil,
      raw_content: html
    )

    document = instance_double('Document', canonical_path: '/tmp/demo.epub').tap do |doc|
      allow(doc).to receive(:get_chapter).with(0).and_return(chapter)
    end

    parser_factory = lambda do |raw|
      EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(raw)
    end

    container = EbookReader::Domain::DependencyContainer.new
    container.register(:xhtml_parser_factory, parser_factory)
    container.register(:logger, nil)
    container.register(:state_store, state_store)
    container.register(:layout_service, layout_service)
    container.register(:document, document)

    formatting_service = EbookReader::Domain::Services::FormattingService.new(container)
    container.register(:formatting_service, formatting_service)

    service = described_class.new(container)
    service.next_page

    expect(state_store.get(%i[reader single_page])).to eq(2)
    expect(state_store.get(%i[reader current_page])).to eq(2)
  end
end

