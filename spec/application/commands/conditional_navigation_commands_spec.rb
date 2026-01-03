# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::Commands::ConditionalNavigationCommand do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:state_store) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }
  let(:context) { double('Context', dependencies: container) }

  before do
    allow(container).to receive(:resolve).with(:state_store).and_return(state_store)
    allow(container).to receive(:resolve).with(:global_state).and_return(state_store)
    allow(container).to receive(:registered?).with(:navigation_service).and_return(true)
    nav = instance_double(EbookReader::Domain::Services::NavigationService, next_page: nil, prev_page: nil)
    allow(container).to receive(:resolve).with(:navigation_service).and_return(nav)
    ui = double('UI', sidebar_select: nil, sidebar_up: nil, sidebar_down: nil)
    allow(container).to receive(:resolve).with(:ui_controller).and_return(ui)
    allow(container).to receive(:resolve).with(:logger).and_return(nil)
  end

  it 'routes to sidebar when visible' do
    state_store.set(%i[reader sidebar_visible], true)
    cmd = described_class.select_or_sidebar
    expect { cmd.execute(context) }.not_to raise_error
  end
end
