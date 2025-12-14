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

  it 'preserves whitespace around inline tags' do
    paragraph = blocks.find { |block| block.type == :paragraph }
    expect(paragraph.text).to eq('First paragraph with emphasis.')
  end

  it 'preserves whitespace-only nodes between inline elements' do
    html = <<~HTML
      <html>
        <body>
          <p><span>Hello</span>
          <span>world</span></p>
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    paragraph = blocks.find { |block| block.type == :paragraph }
    expect(paragraph.text).to eq('Hello world')
  end

  it 'does not flatten container divs containing block children' do
    html = <<~HTML
      <html>
        <body>
          <div>
            <p>One</p>
            <p>Two</p>
          </div>
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    expect(blocks.map(&:text)).to include('One', 'Two')
    expect(blocks.count { |b| b.type == :paragraph }).to be >= 2
  end

  it 'creates placeholders for images' do
    html = <<~HTML
      <html>
        <body>
          <img src="cover.png" alt="Cover image" />
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    expect(blocks.any? { |b| b.type == :image }).to be(true)
    expect(blocks.map(&:text).join("\n")).to include('[Image]')
    expect(blocks.map(&:text).join("\n")).not_to include('Cover image')
  end

  it 'does not use the src filename when alt is missing' do
    html = <<~HTML
      <html>
        <body>
          <img src="cover.png" />
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    combined = blocks.map(&:text).join("\n")
    expect(combined).to include('[Image]')
    expect(combined).not_to include('cover.png')
  end

  it 'does not show filename-like alt text in placeholders' do
    html = <<~HTML
      <html>
        <body>
          <img src="cover.png" alt="img19.jpg" />
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    combined = blocks.map(&:text).join("\n")
    expect(combined).to include('[Image]')
    expect(combined).not_to include('img19.jpg')
  end

  it 'decodes common HTML entities (e.g. &nbsp; and &mdash;)' do
    html = <<~HTML
      <html>
        <body>
          <p>A&nbsp;B &mdash; C</p>
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    expect(blocks.map(&:text).join(' ')).to include('A B — C')
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
