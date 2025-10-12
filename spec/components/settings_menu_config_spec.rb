# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings menu configuration toggles' do
  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:menu) { EbookReader::MainMenu.new(container) }
  let(:dispatcher) { menu.instance_variable_get(:@dispatcher) }
  let(:state) { menu.state }
  let(:controller) { menu.instance_variable_get(:@controller) }

  before do
    state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(page_numbering_mode: :absolute))
    state.save_config if state.respond_to?(:save_config)
    dispatcher.activate(:settings)
  end

  it 'toggles page numbering mode when pressing 4' do
    expect(state.get(%i[config page_numbering_mode])).to eq(:absolute)

    dispatcher.handle_key('4')

    expect(state.get(%i[config page_numbering_mode])).to eq(:dynamic)

    dispatcher.handle_key('4')

    expect(state.get(%i[config page_numbering_mode])).to eq(:absolute)
  end
end
