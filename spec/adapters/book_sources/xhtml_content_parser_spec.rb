# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Epub::Parsers::XHTMLContentParser do
  it 'parses paragraphs into content blocks with segments' do
    parser = described_class.new('<html><body><p>Hello <em>World</em></p></body></html>')

    blocks = parser.parse

    expect(blocks).not_to be_empty
    first = blocks.first
    expect(first).to be_a(Shoko::Core::Models::ContentBlock)
    expect(first.segments).not_to be_empty
    expect(first.text).to include('Hello')
  end
end
