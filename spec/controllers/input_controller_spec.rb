# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::InputController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }
  let(:ui) { double('UI', handle_popup_action: nil, cleanup_popup_state: nil, switch_mode: nil) }

  class FakeDeps
    def initialize(ui) = @ui = ui

    def resolve(name)
      name == :ui_controller ? @ui : nil
    end
  end

  subject(:ic) { described_class.new(state, FakeDeps.new(ui)) }

  it 'handles popup selection change/action/cancel' do
    popup = double('Popup')
    allow(popup).to receive(:handle_key).and_return({ type: :selection_change })
    state.set(%i[reader popup_menu], popup)
    expect(ic.handle_popup_navigation('j')).to eq(:handled)

    allow(popup).to receive(:handle_key).and_return({ type: :action, action: :x })
    expect(ic.handle_popup_action_key('\r')).to eq(:handled)
    expect(ui).to have_received(:handle_popup_action)

    allow(popup).to receive(:handle_key).and_return({ type: :cancel })
    expect(ic.handle_popup_cancel('q')).to eq(:handled)
    expect(ui).to have_received(:cleanup_popup_state)
  end
end
