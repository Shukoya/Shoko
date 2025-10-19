# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Commands::SidebarCommand do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:state_store) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }
  let(:context) { double('Context', dependencies: container) }

  before do
    allow(container).to receive(:resolve).with(:state_store).and_return(state_store)
    ui = double('UI', sidebar_up: nil, sidebar_down: nil, sidebar_select: nil)
    allow(container).to receive(:resolve).with(:ui_controller).and_return(ui)
    allow(container).to receive(:resolve).with(:logger).and_return(nil)
  end

  it 'invokes UI controller for down action' do
    expect(container.resolve(:ui_controller)).to receive(:sidebar_down)
    described_class.new(:down).execute(context)
  end
end
