# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::Components::PopupMenu do
  let(:menu) { described_class.new(5, 5, %w[One Two]) }

  it 'tracks selected item with keyboard navigation' do
    expect(menu.get_selected_item).to eq('One')
    menu.move_selection(1)
    expect(menu.get_selected_item).to eq('Two')
  end

  it 'detects clicks inside its bounds' do
    item = menu.handle_click(6, 5)
    expect(item).to eq('One')
    expect(menu.selected_index).to eq(0)
  end

  it 'returns nil for clicks outside bounds' do
    expect(menu.handle_click(0, 0)).to be_nil
  end
end
