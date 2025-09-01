# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'StateStore extras' do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:store) { EbookReader::Infrastructure::StateStore.new(bus) }

  describe 'terminal size helpers' do
    it 'updates terminal size fields consistently' do
      store.update_terminal_size(100, 40)
      expect(store.get(%i[reader last_width])).to eq(100)
      expect(store.get(%i[ui terminal_height])).to eq(40)
    end
  end

  describe 'snapshot/restore' do
    it 'creates and restores reader snapshot' do
      store.set(%i[reader current_chapter], 2)
      snap = store.reader_snapshot
      expect(snap[:current_chapter]).to eq(2)

      store.restore_reader_from({ 'current_chapter' => 1, 'page_offset' => 3, 'mode' => 'read' })
      expect(store.get(%i[reader current_chapter])).to eq(1)
      expect(store.get(%i[reader single_page])).to eq(3)
    end
  end
end

