# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/domain/services/formatting_service'
require 'ebook_reader/domain/models/content_block'

RSpec.describe EbookReader::Domain::Services::FormattingService do
  let(:service) { described_class.new(nil) }
  let(:html) do
    <<~HTML
      <html><body>
        <h2>Heading</h2>
        <p>Paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
        <ul><li>First bullet</li><li>Second bullet</li></ul>
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
      raw_content: html
    )
  end
  let(:document) do
    instance_double('Document', canonical_path: '/tmp/demo.epub').tap do |doc|
      allow(doc).to receive(:get_chapter).with(0).and_return(chapter)
    end
  end

  describe '#ensure_formatted!' do
    it 'populates chapter blocks and lines' do
      service.ensure_formatted!(document, 0, chapter)

      expect(chapter.blocks).not_to be_nil
      expect(chapter.lines).not_to be_empty
      heading_block = chapter.blocks.find { |block| block.type == :heading }
      expect(heading_block.text).to include('Heading')
    end
  end

  describe '#wrap_window' do
    before do
      service.ensure_formatted!(document, 0, chapter)
    end

    it 'returns display lines with styling metadata' do
      lines = service.wrap_window(document, 0, 40, 0, 5)
      expect(lines).not_to be_empty
      first = lines.first
      expect(first).to respond_to(:segments)
      expect(first.segments.first.text).to include('Heading')
      expect(first.metadata[:block_type]).to eq(:heading)
    end
  end
end
