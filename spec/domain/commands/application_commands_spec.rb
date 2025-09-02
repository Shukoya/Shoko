# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Commands::ApplicationCommand do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:state_store) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }
  let(:context) do
    double('Context', dependencies: container)
  end

  before do
    allow(container).to receive(:resolve).with(:state_store).and_return(state_store)
    allow(container).to receive(:registered?).and_return(false)
  end

  it 'sets help mode via show_help' do
    cmd = described_class.new(:show_help)
    cmd.execute(context)
    expect(state_store.get(%i[reader mode])).to eq(:help)
  end

  it 'toggles view mode when controller hook not present' do
    state_store.set(%i[reader view_mode], :split)
    cmd = described_class.new(:toggle_view_mode)
    cmd.execute(context)
    expect(state_store.get(%i[reader view_mode])).to eq(:single)
  end
end
