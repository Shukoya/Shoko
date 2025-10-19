# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Selectors::ConfigSelectors do
  let(:state) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }

  it 'reads basic config values' do
    expect(described_class.view_mode(state)).to eq(:split)
    expect(described_class.show_page_numbers?(state)).to be true
    expect(%i[absolute dynamic]).to include(described_class.page_numbering_mode(state))
  end

  it 'reads additional config flags and theme' do
    expect(described_class.line_spacing(state)).to eq(:compact)
    expect(described_class.highlight_quotes?(state)).to be true
    expect(described_class.highlight_keywords?(state)).to be false
    expect(%i[dark default]).to include(described_class.theme(state))
    expect(described_class.config_hash(state)).to be_a(Hash)
  end
end
