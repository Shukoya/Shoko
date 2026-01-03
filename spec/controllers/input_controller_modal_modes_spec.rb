# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/controllers/input_controller'
require 'ebook_reader/input/dispatcher'
require 'ebook_reader/application/commands/annotation_editor_commands'

RSpec.describe EbookReader::Controllers::InputController do
  let(:state) { instance_double('StateStore', get: :read, dispatch: nil) }
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:input_controller) { described_class.new(state, container) }

  let(:ui_controller) do
    instance_double('UIController', cleanup_popup_state: nil, switch_mode: nil)
  end

  let(:state_controller) do
    instance_double('StateController', quit_to_menu: nil)
  end

  let(:reader_context) do
    instance_double('ReaderContext',
                    dependencies: container,
                    current_editor_component: nil,
                    quit_to_menu: nil)
  end

  let(:overlay_session) do
    instance_double('OverlaySession',
                    save_annotation: :handled,
                    cancel_annotation: :handled,
                    handle_backspace: :handled,
                    handle_enter: :handled,
                    handle_character: :handled)
  end

  before do
    container.register(:ui_controller, ui_controller)
    container.register(:state_controller, state_controller)
    input_controller.setup_input_dispatcher(reader_context)
  end

  it 'routes quit key to quit_to_menu in read mode' do
    expect(state_controller).to receive(:quit_to_menu).once
    input_controller.handle_key('q')
  end

  it 'intercepts keys with annotation editor modal mode' do
    allow(reader_context).to receive(:current_editor_component).and_return(overlay_session)
    expect(overlay_session).to receive(:handle_character).with('q')
    expect(state_controller).not_to receive(:quit_to_menu)

    input_controller.enter_modal_mode(:annotation_editor)
    input_controller.handle_key('q')
    input_controller.exit_modal_mode(:annotation_editor)
  end
end
