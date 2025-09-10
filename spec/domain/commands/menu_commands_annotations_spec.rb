# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Commands::MenuCommand do
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(EbookReader::Infrastructure::EventBus.new) }

  # Minimal fake annotations screen
  class FakeAnnotationsScreen
    attr_reader :navigations, :current_annotation, :current_book_path

    def initialize
      @navigations = []
      @current_annotation = { 'id' => '1', 'text' => 't', 'note' => 'n', 'range' => { 'start' => 0, 'end' => 1 }, 'chapter_index' => 0 }
      @current_book_path = '/tmp/book.epub'
    end

    def navigate(dir) = @navigations << dir
  end

  class FakeMainMenuComponent
    attr_reader :annotations_screen

    def initialize
      @annotations_screen = FakeAnnotationsScreen.new
    end
  end

  class Ctx
    attr_reader :state, :main_menu_component, :calls

    def initialize(state)
      @state = state
      @main_menu_component = FakeMainMenuComponent.new
      @calls = []
    end

    def open_selected_annotation = @calls << :open_selected_annotation
    def open_selected_annotation_for_edit = @calls << :open_selected_annotation_for_edit
    def delete_selected_annotation = @calls << :delete_selected_annotation
    def switch_to_mode(mode) = @calls << [:switch_to_mode, mode]
  end

  let(:ctx) { Ctx.new(state) }

  it 'navigates annotation list up/down' do
    described_class.new(:annotations_up).execute(ctx)
    described_class.new(:annotations_down).execute(ctx)
    expect(ctx.main_menu_component.annotations_screen.navigations).to eq(%i[up down])
  end

  it 'selects annotation and switches to detail' do
    described_class.new(:annotations_select).execute(ctx)
    expect(ctx.state.get(%i[menu selected_annotation])).to be_a(Hash)
    expect(ctx.state.get(%i[menu selected_annotation_book])).to be_a(String)
    expect(ctx.calls).to include(%i[switch_to_mode annotation_detail])
  end

  it 'invokes annotation edit and delete' do
    described_class.new(:annotations_edit).execute(ctx)
    described_class.new(:annotations_delete).execute(ctx)
    expect(ctx.calls).to include(:open_selected_annotation_for_edit, :delete_selected_annotation)
  end

  it 'handles annotation detail actions' do
    described_class.new(:annotation_detail_open).execute(ctx)
    described_class.new(:annotation_detail_edit).execute(ctx)
    described_class.new(:annotation_detail_delete).execute(ctx)
    described_class.new(:annotation_detail_back).execute(ctx)
    expect(ctx.calls).to include(:open_selected_annotation, :open_selected_annotation_for_edit)
    expect(ctx.calls).to include(%i[switch_to_mode annotations])
  end
end
