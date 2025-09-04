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

  it 'reads various reader selectors' do
    state.set(%i[reader current_chapter], 1)
    expect(described_class.current_chapter(state)).to eq(1)
    state.set(%i[reader left_page], 5)
    expect(described_class.left_page(state)).to eq(5)
    state.set(%i[reader total_pages], 10)
    expect(described_class.total_pages(state)).to eq(10)
    expect(described_class.rendered_lines(state)).to be_a(Hash)
    state.set(%i[reader sidebar_active_tab], :toc)
    expect(described_class.sidebar_active_tab(state)).to eq(:toc)
  end
end
