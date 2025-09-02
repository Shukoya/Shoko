# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Screens::AnnotationEditorScreenComponent do
  let(:svc) { double('AnnotationService', add: true, update: true) }

  class FakeUIForEditor
    attr_reader :dependencies

    def initialize(svc, state)
      @state = state
      @dependencies = Class.new do
        def initialize(svc) = (@svc = svc)
        def resolve(name) = (name == :annotation_service ? @svc : nil)
      end.new(svc)
    end

    def current_book_path = '/tmp/book.epub'
    def refresh_annotations; end
    def cleanup_popup_state; end
    def set_message(_); end
    def switch_mode(_); end
  end

  before { mock_terminal }

  it 'uses service to add a new annotation' do
    state = EbookReader::Infrastructure::ObserverStateStore.new(EbookReader::Infrastructure::EventBus.new)
    ui = FakeUIForEditor.new(svc, state)
    comp = described_class.new(ui, text: 'T', range: { start: { x: 0, y: 0 }, end: { x: 1, y: 0 } }, chapter_index: 0, dependencies: ui.dependencies)
    expect(svc).to receive(:add).with('/tmp/book.epub', 'T', any_args)

    surface = EbookReader::Components::Surface.new(EbookReader::Terminal)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 24)
    comp.render(surface, bounds)
    comp.save_annotation
  end

  it 'uses service to update an existing annotation' do
    state = EbookReader::Infrastructure::ObserverStateStore.new(EbookReader::Infrastructure::EventBus.new)
    ui = FakeUIForEditor.new(svc, state)
    ann = { 'id' => '123', 'note' => 'N', 'text' => 'T', 'range' => { start: { x: 0, y: 0 }, end: { x: 1, y: 0 } }, 'chapter_index' => 0 }
    comp = described_class.new(ui, annotation: ann, dependencies: ui.dependencies)
    expect(svc).to receive(:update).with('/tmp/book.epub', '123', any_args)

    surface = EbookReader::Components::Surface.new(EbookReader::Terminal)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 24)
    comp.render(surface, bounds)
    comp.save_annotation
  end
end
