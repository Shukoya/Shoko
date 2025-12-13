# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::FormattingService do
  let(:parser_factory) do
    lambda do |raw|
      EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(raw)
    end
  end
  let(:dependencies) do
    instance_double(EbookReader::Domain::DependencyContainer).tap do |deps|
      allow(deps).to receive(:resolve).with(:xhtml_parser_factory).and_return(parser_factory)
      allow(deps).to receive(:resolve).with(:logger).and_return(nil)
    end
  end
  let(:service) { described_class.new(dependencies) }

  it 'assigns stable, distinct placement ids for multiple images' do
    allow(EbookReader::Infrastructure::KittyGraphics).to receive(:supported?).and_return(true)

    html = <<~HTML
      <html><body>
        <img src="img1.jpg" alt="One" />
        <p>Text</p>
        <img src="img2.jpeg" alt="Two" />
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

    config = instance_double('ConfigStore')
    allow(config).to receive(:get).and_return(nil)
    allow(config).to receive(:get).with(%i[config kitty_images]).and_return(true)

    lines = service.wrap_all(document, 0, 60, config: config)
    render_lines = Array(lines).select do |line|
      line.respond_to?(:metadata) && line.metadata.is_a?(Hash) && line.metadata[:image_render_line] == true
    end

    expect(render_lines.length).to eq(2)

    ids = render_lines.map { |line| line.metadata.dig(:image_render, :placement_id) }
    expect(ids.compact.length).to eq(2)
    expect(ids.uniq.length).to eq(2)
  end
end

