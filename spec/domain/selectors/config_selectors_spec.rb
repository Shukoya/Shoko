# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Selectors::ConfigSelectors do
  let(:state) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }

  it 'reads basic config values' do
    expect(described_class.view_mode(state)).to eq(:split)
    expect(described_class.show_page_numbers?(state)).to be true
    expect(%i[absolute dynamic]).to include(described_class.page_numbering_mode(state))
  end
end
