# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Selectors::MenuSelectors do
  let(:state) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }

  it 'exposes menu selection and file input fields' do
    expect(described_class.selected(state)).to eq(0)
    expect(described_class.file_input(state)).to eq('')
    expect([true, false]).to include(described_class.search_active?(state))
  end
end
