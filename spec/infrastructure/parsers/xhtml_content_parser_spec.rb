# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/infrastructure/parsers/xhtml_content_parser'
require 'ebook_reader/domain/models/content_block'

RSpec.describe EbookReader::Infrastructure::Parsers::XHTMLContentParser do
  let(:html) do
    <<~HTML
      <html>
        <body>
          <h1>Chapter Title</h1>
          <p>First <strong>paragraph</strong> with <em>emphasis</em>.</p>
          <ul>
            <li>Item one</li>
            <li>Item two</li>
          </ul>
          <blockquote>
            <p>Quoted text.</p>
          </blockquote>
          <pre><code>code sample\nsecond line</code></pre>
        </body>
      </html>
    HTML
  end

  subject(:blocks) { described_class.new(html).parse }

  it 'extracts headings, paragraphs, lists, quotes, and code blocks' do
    types = blocks.map(&:type)
    expect(types).to include(:heading, :paragraph, :list_item, :quote, :code)
  end

  it 'preserves inline emphasis as segment styles' do
    paragraph = blocks.find { |block| block.type == :paragraph }
    bold_segment = paragraph.segments.find { |seg| seg.styles[:bold] }
    italic_segment = paragraph.segments.find { |seg| seg.styles[:italic] }

    expect(bold_segment.text).to include('paragraph')
    expect(italic_segment.text).to include('emphasis')
  end

  it 'annotates list items with markers and levels' do
    list_items = blocks.select { |block| block.type == :list_item }
    expect(list_items.count).to eq(2)
    expect(list_items.first.metadata[:marker]).to eq('•')
    expect(list_items.first.level).to eq(1)
  end

  it 'marks quote blocks as quoted in metadata' do
    quote = blocks.find { |block| block.metadata && block.metadata[:quoted] }
    expect(quote).not_to be_nil
    expect(quote.text).to include('Quoted text')
  end

  it 'treats pre/code blocks as preserved whitespace' do
    code_block = blocks.find { |block| block.type == :code }
    expect(code_block.segments.first.text).to include('code sample')
  end
end
