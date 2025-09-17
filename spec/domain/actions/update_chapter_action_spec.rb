# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Actions::UpdateChapterAction do
  it 'updates current chapter and synchronizes toc selections' do
    action = described_class.new(5)
    state = EbookReader::Infrastructure::ObserverStateStore.new(EbookReader::Infrastructure::EventBus.new)
    state.update(%i[reader toc_selected] => 0,
                 %i[reader sidebar_toc_selected] => 0,
                 %i[reader current_chapter] => 0)

    action.apply(state)

    expect(state.get(%i[reader current_chapter])).to eq(5)
    expect(state.get(%i[reader toc_selected])).to eq(5)
    expect(state.get(%i[reader sidebar_toc_selected])).to eq(5)
  end
end
