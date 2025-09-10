# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::UIController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  class DepsUI
    def initialize(doc: nil, nav: nil, input: nil)
      @doc = doc
      @nav = nav
      @input = input
    end

    def resolve(name)
      return @doc if name == :document
      return @nav if name == :navigation_service
      return @input if name == :input_controller

      nil
    end
  end

  it 'toggles TOC sidebar and restores previous view mode' do
    # Initial setup
    state.update({ %i[config view_mode] => :split })
    doc = instance_double('Doc', chapters: Array.new(3) { |i| double("c#{i}") })
    controller = described_class.new(state, DepsUI.new(doc: doc))

    # Open TOC sidebar
    controller.open_toc
    expect(state.get(%i[reader sidebar_visible])).to be true
    expect(state.get(%i[reader sidebar_active_tab])).to eq(:toc)
    expect(state.get(%i[config view_mode])).to eq(:single)

    # Close TOC sidebar (toggles)
    controller.open_toc
    expect(state.get(%i[reader sidebar_visible])).to be false
    # View mode should be restored to split
    expect(state.get(%i[config view_mode])).to eq(:split)
  end

  it 'sidebar_select jumps to selected chapter via navigation service and closes' do
    state.update({ %i[reader sidebar_visible] => true, %i[reader sidebar_active_tab] => :toc,
                   %i[reader sidebar_toc_selected] => 2 })
    nav = instance_double('Nav', jump_to_chapter: true)
    controller = described_class.new(state, DepsUI.new(nav: nav))

    expect(nav).to receive(:jump_to_chapter).with(2)
    controller.sidebar_select
    expect(state.get(%i[reader sidebar_visible])).to be false
  end
end
