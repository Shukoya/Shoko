# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Helpers::TextMetrics do
  describe '.visible_length' do
    it 'counts double-width characters correctly' do
      expect(described_class.visible_length('漢')).to eq(2)
    end

    it 'treats soft hyphen as zero width' do
      text = "soft\u00AD"
      expect(described_class.visible_length(text)).to eq(4)
    end

    it 'expands tabs when measuring length' do
      expect(described_class.visible_length("\t"))
        .to eq(EbookReader::Helpers::TextMetrics::TAB_SIZE)
    end
  end

  describe '.wrap_plain_text' do
    it 'wraps text based on grapheme cell widths' do
      line = '漢字漢字 example text'
      wrapped = described_class.wrap_plain_text(line, 6)
      expect(wrapped.first).to include('漢字')
      expect(wrapped[1]).to include('example')
    end

    it 'preserves blank lines' do
      expect(described_class.wrap_plain_text('   ', 10)).to eq([''])
    end
  end
end
