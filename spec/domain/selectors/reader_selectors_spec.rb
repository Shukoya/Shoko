# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Selectors::ReaderSelectors do
  let(:state) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }

  it 'reports sidebar flags and terminal size' do
    expect(described_class.sidebar_visible?(state)).to be false
    state.set(%i[reader sidebar_visible], true)
    expect(described_class.sidebar_visible?(state)).to be true
    expect(described_class.last_width(state)).to be_a(Integer)
  end
end

