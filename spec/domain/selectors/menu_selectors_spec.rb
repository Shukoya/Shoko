# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Selectors::MenuSelectors do
  let(:state) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }

  it 'exposes menu selection and file input fields' do
    expect(described_class.selected(state)).to eq(0)
    expect(described_class.selected_item(state)).to eq(0)
    expect(described_class.file_input(state)).to eq('')
    expect([true, false]).to include(described_class.search_active?(state))
  end

  it 'reads mode, browse selection and search flags' do
    expect(described_class.mode(state)).to eq(:menu)
    state.set(%i[menu browse_selected], 2)
    expect(described_class.browse_selected(state)).to eq(2)
    state.set(%i[menu search_active], true)
    expect(described_class.search_active?(state)).to be true
    state.set(%i[menu search_query], 'abc')
    expect(described_class.search_query(state)).to eq('abc')
    state.set(%i[menu search_cursor], 3)
    expect(described_class.search_cursor(state)).to eq(3)
  end
end
