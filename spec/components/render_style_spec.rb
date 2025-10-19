# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::RenderStyle do
  describe '.styled_segment' do
    let(:heading_code) { described_class.color(:heading) }
    let(:primary_code) { described_class.color(:primary) }

    it 'uses accent for headings when highlighting is enabled' do
      result = described_class.styled_segment('Title', {}, metadata: { block_type: :heading, highlight_enabled: true })
      expect(result).to start_with(heading_code)
    end

    it 'falls back to primary color for headings when highlighting is disabled' do
      result = described_class.styled_segment('Title', {}, metadata: { block_type: :heading, highlight_enabled: false })
      expect(result).to start_with(primary_code)
    end
  end
end
