# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/controllers/input_controller'
require 'ebook_reader/input/dispatcher'
require 'ebook_reader/domain/commands/annotation_editor_commands'

RSpec.describe EbookReader::Controllers::InputController do
  let(:state) { instance_double('StateStore', get: :read, dispatch: nil) }
  let(:dependencies) { instance_double('Dependencies') }
  let(:input_controller) { described_class.new(state, dependencies) }

  let(:ui_controller) do
    instance_double('UIController', cleanup_popup_state: nil, switch_mode: nil)
  end

  let(:context_dependencies) do
    instance_double('ContextDependencies').tap do |deps|
      allow(deps).to receive(:resolve).with(:ui_controller).and_return(ui_controller)
    end
  end

  let(:reader_context) do
    instance_double('ReaderContext',
                    dependencies: context_dependencies,
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
    allow(dependencies).to receive(:resolve)
    input_controller.setup_input_dispatcher(reader_context)
  end

  it 'routes quit key to quit_to_menu in read mode' do
    expect(reader_context).to receive(:quit_to_menu).once
    input_controller.handle_key('q')
  end

  it 'intercepts keys with annotation editor modal mode' do
    allow(reader_context).to receive(:current_editor_component).and_return(overlay_session)
    expect(overlay_session).to receive(:handle_character).with('q')
    expect(reader_context).not_to receive(:quit_to_menu)

    input_controller.enter_modal_mode(:annotation_editor)
    input_controller.handle_key('q')
    input_controller.exit_modal_mode(:annotation_editor)
  end
end
