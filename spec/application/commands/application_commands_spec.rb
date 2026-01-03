# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::Commands::ApplicationCommand do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:state_store) { EbookReader::Infrastructure::StateStore.new(EbookReader::Infrastructure::EventBus.new) }
  let(:context) { double('Context', dependencies: container) }

  before do
    container.register(:state_store, state_store)
  end

  describe '#execute' do
    it 'delegates quit_to_menu to the state controller when available' do
      state_controller = instance_double('StateController', quit_to_menu: true)
      container.register(:state_controller, state_controller)

      described_class.new(:quit_to_menu).execute(context)

      expect(state_controller).to have_received(:quit_to_menu)
    end

    it 'dispatches quit action when no controller is registered' do
      described_class.new(:quit_to_menu).execute(context)
      expect(state_store.get(%i[reader running])).to eq(false)
    end

    it 'invokes UI controller for toggle_view_mode when present' do
      ui_controller = instance_double('UIController', toggle_view_mode: true)
      container.register(:ui_controller, ui_controller)

      described_class.new(:toggle_view_mode).execute(context)

      expect(ui_controller).to have_received(:toggle_view_mode)
    end

    it 'toggles view mode via state store when UI controller missing' do
      state_store.set(%i[config view_mode], :split)

      described_class.new(:toggle_view_mode).execute(context)

      expect(state_store.get(%i[config view_mode])).to eq(:single)
    end

    it 'opens help via UI controller when present' do
      ui_controller = instance_double('UIController', show_help: true)
      container.register(:ui_controller, ui_controller)

      described_class.new(:show_help).execute(context)

      expect(ui_controller).to have_received(:show_help)
    end

    it 'falls back to state store when UI controller missing for help' do
      described_class.new(:show_help).execute(context)
      expect(state_store.get(%i[reader mode])).to eq(:help)
    end

    it 'delegates quit_application to state controller when available' do
      state_controller = instance_double('StateController', quit_application: true)
      container.register(:state_controller, state_controller)

      described_class.new(:quit_application).execute(context)

      expect(state_controller).to have_received(:quit_application)
    end

    it 'cleans up terminal and exits when controller missing' do
      terminal_service = instance_double('TerminalService', force_cleanup: nil)
      container.register(:terminal_service, terminal_service)
      allow(Kernel).to receive(:exit)

      described_class.new(:quit_application).execute(context)

      expect(terminal_service).to have_received(:force_cleanup)
      expect(Kernel).to have_received(:exit).with(0)
    end
  end
end
