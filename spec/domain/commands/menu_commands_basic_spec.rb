# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Commands::MenuCommand do
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(EbookReader::Infrastructure::EventBus.new) }
  let(:ctx) do
    double('Ctx', state: state, handle_menu_selection: nil, cleanup_and_exit: nil,
                  switch_to_browse: nil, switch_to_search: nil, switch_to_mode: nil)
  end

  it 'navigates main menu up/down and selects' do
    EbookReader::Domain::Commands::MenuCommand.new(:menu_up).execute(ctx)
    EbookReader::Domain::Commands::MenuCommand.new(:menu_down).execute(ctx)
    expect(state.get(%i[menu selected])).to be_a(Integer)
    expect { EbookReader::Domain::Commands::MenuCommand.new(:menu_select).execute(ctx) }.not_to raise_error
  end

  it 'starts and exits search' do
    minimal_ctx = Struct.new(:state).new(state)
    expect(state.get(%i[menu mode])).to eq(:menu)
    EbookReader::Domain::Commands::MenuCommand.new(:start_search).execute(minimal_ctx)
    expect(state.get(%i[menu mode])).to eq(:search)
    EbookReader::Domain::Commands::MenuCommand.new(:exit_search).execute(minimal_ctx)
    expect(state.get(%i[menu mode])).to eq(:browse)
  end

  it 'browses list up/down' do
    EbookReader::Domain::Commands::MenuCommand.new(:browse_up).execute(ctx)
    EbookReader::Domain::Commands::MenuCommand.new(:browse_down).execute(ctx)
    expect(state.get(%i[menu browse_selected])).to be_a(Integer)
  end
end
