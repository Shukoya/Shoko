# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::UIController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  # Minimal fake container
  class FakeContainer
    def initialize(map) = (@map = map)
    def resolve(name) = @map.fetch(name)
    def registered?(name) = @map.key?(name)
  end

  let(:input_controller) { double('InputController', activate_for_mode: nil) }
  let(:navigation_service) { double('NavService', jump_to_chapter: nil) }
  let(:selection_service) { double('SelectionService', extract_text: 'txt') }
  let(:clipboard) { double('Clipboard', available?: true, copy_with_feedback: true) }
  let(:document) do
    double('Doc', chapters: Array.new(5) { |i| double("Ch#{i}") })
  end
  let(:container) do
    FakeContainer.new(
      input_controller: input_controller,
      navigation_service: navigation_service,
      selection_service: selection_service,
      clipboard_service: clipboard,
      document: document
    )
  end

  subject(:ui) { described_class.new(state, container) }

  it 'switches modes and notifies input controller' do
    ui.switch_mode(:help)
    expect(state.get(%i[reader mode])).to eq(:help)
    expect(input_controller).to have_received(:activate_for_mode).with(:help)
  end

  it 'toggles TOC sidebar open/close and restores view mode' do
    state.set(%i[config view_mode], :split)
    state.set(%i[reader current_chapter], 1)
    ui.open_toc
    expect(state.get(%i[reader sidebar_visible])).to be true
    expect(state.get(%i[config view_mode])).to eq(:single)

    ui.open_toc
    expect(state.get(%i[reader sidebar_visible])).to be false
    expect(state.get(%i[config view_mode])).to eq(:split)
  end

  it 'changes view mode and line spacing' do
    state.set(%i[config view_mode], :split)
    ui.toggle_view_mode
    expect(state.get(%i[config view_mode])).to eq(:single)

    state.set(%i[config line_spacing], :normal)
    ui.increase_line_spacing
    expect(state.get(%i[config line_spacing])).to eq(:relaxed)
    ui.decrease_line_spacing
    expect(state.get(%i[config line_spacing])).to eq(:normal)
  end

  it 'navigates sidebar toc selection and selects' do
    state.set(%i[reader sidebar_visible], true)
    state.set(%i[reader sidebar_active_tab], :toc)
    state.set(%i[reader sidebar_toc_selected], 0)
    ui.sidebar_down
    expect(state.get(%i[reader sidebar_toc_selected])).to eq(1)

    # Select and close, restore view
    state.set(%i[config view_mode], :split)
    state.set(%i[reader sidebar_prev_view_mode], :split)
    ui.sidebar_select
    expect(navigation_service).to have_received(:jump_to_chapter)
    expect(state.get(%i[reader sidebar_visible])).to be false
    expect(state.get(%i[config view_mode])).to eq(:split)
  end

  it 'handles popup copy action with clipboard available' do
    state.set(%i[reader rendered_lines], {})
    state.set(%i[reader selection], { start: { x: 1, y: 1 }, end: { x: 1, y: 1 } })
    ui.handle_popup_action({ action: :copy_to_clipboard, data: { selection_range: state.get(%i[reader selection]) } })
    expect(state.get(%i[reader mode])).to eq(:read)
  end

  it 'cleans up popup state' do
    state.set(%i[reader popup_menu], Object.new)
    state.set(%i[reader selection], { a: 1 })
    ui.cleanup_popup_state
    expect(state.get(%i[reader popup_menu])).to be_nil
    expect(state.get(%i[reader selection])).to be_nil
  end
end
