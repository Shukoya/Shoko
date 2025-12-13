# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::Internal::DynamicPageMapBuilder do
  def dl(text, metadata = {})
    EbookReader::Domain::Models::DisplayLine.new(text: text, segments: [], metadata: metadata)
  end

  it 'keeps image blocks together when paginating' do
    doc = instance_double('Doc', chapter_count: 1)
    chapter = EbookReader::Domain::Models::Chapter.new(
      number: '1',
      title: 'Demo',
      lines: [],
      metadata: { source_path: 'OEBPS/ch1.xhtml' },
      blocks: nil,
      raw_content: nil
    )
    allow(doc).to receive(:get_chapter).with(0).and_return(chapter)

    image_meta = { block_type: :image, image: { src: 'img1.jpg', alt: 'One' } }
    render_payload = { cols: 80, rows: 3, placement_id: 123 }
    wrapped = [
      dl('one', block_type: :paragraph),
      dl('two', block_type: :paragraph),
      dl('three', block_type: :paragraph),
      dl('', image_meta.merge(image_render_line: true, image_render: render_payload, image_line_index: 0)),
      dl('', image_meta.merge(image_render_line: false, image_render: render_payload, image_line_index: 1, image_spacer: true)),
      dl('', image_meta.merge(image_render_line: false, image_render: render_payload, image_line_index: 2, image_spacer: true)),
      dl('[Image: img1.jpg]', image_meta.merge(image_caption: true)),
      dl('after', block_type: :paragraph),
    ]

    formatter = instance_double('Formatter')
    allow(formatter).to receive(:wrap_all).and_return(wrapped)

    pages = described_class.build(doc, 80, 6, formatter: formatter)

    expect(pages.length).to eq(2)
    expect(pages[0][:start_line]).to eq(0)
    expect(pages[0][:end_line]).to eq(2)
    expect(pages[0][:lines].length).to eq(3)
    expect(pages[0][:lines].any? { |line| line.respond_to?(:metadata) && line.metadata[:block_type] == :image }).to eq(false)

    expect(pages[1][:start_line]).to eq(3)
    expect(pages[1][:end_line]).to eq(7)
    expect(pages[1][:lines].length).to eq(5)
    expect(pages[1][:lines].count { |line| line.respond_to?(:metadata) && line.metadata[:block_type] == :image }).to eq(4)
    expect(pages[1][:lines].first.metadata[:image_render_line]).to eq(true)
    expect(pages[1][:total_pages_in_chapter]).to eq(2)
    expect(pages[0][:total_pages_in_chapter]).to eq(2)
  end
end

