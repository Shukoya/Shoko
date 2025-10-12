# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::PendingJumpHandler do
  let(:state_store) { EbookReader::Infrastructure::ObserverStateStore.new }
  let(:dependencies) { instance_double('DependencyContainer') }
  let(:ui_controller) { instance_double('UIController') }

  subject(:handler) { described_class.new(state_store, dependencies, ui_controller) }

  before do
    allow(dependencies).to receive(:respond_to?).with(:resolve).and_return(true)
    allow(dependencies).to receive(:resolve) { |key| raise KeyError, key }
    allow(ui_controller).to receive(:open_annotation_editor_overlay)
  end

  describe '#apply' do
    it 'does nothing when no pending jump exists' do
      expect { handler.apply }.not_to raise_error
    end

    it 'jumps to the requested chapter when navigation service is available' do
      state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: { chapter_index: 2 }))
      navigation = instance_double('NavigationService', jump_to_chapter: true)
      allow(dependencies).to receive(:resolve).with(:navigation_service).and_return(navigation)

      handler.apply

      expect(navigation).to have_received(:jump_to_chapter).with(2)
    end

    it 'normalizes selection through coordinate service when provided' do
      selection = { start: { row: 1, col: 1 }, end: { row: 1, col: 5 } }
      normalized = selection.merge(normalized: true)
      state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: { selection_range: selection }))
      coordinate = instance_double('CoordinateService')
      allow(coordinate).to receive(:normalize_selection_range).and_return(normalized)
      allow(dependencies).to receive(:resolve).with(:coordinate_service).and_return(coordinate)

      handler.apply

      expect(coordinate).to have_received(:normalize_selection_range).with(selection, {})
      expect(state_store.get(%i[reader selection])).to eq(normalized)
    end

    it 'prefers selection service normalization when available' do
      selection = { start: { row: 0, col: 0 }, end: { row: 0, col: 3 } }
      normalized = selection.merge(anchors: true)
      state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: { selection_range: selection }))

      selection_service = instance_double('SelectionService', normalize_range: normalized)
      allow(dependencies).to receive(:resolve).with(:selection_service).and_return(selection_service)
      coordinate = instance_double('CoordinateService')
      allow(dependencies).to receive(:resolve).with(:coordinate_service).and_return(coordinate)
      allow(coordinate).to receive(:normalize_selection_range)

      handler.apply

      expect(selection_service).to have_received(:normalize_range).with(state_store, selection)
      expect(coordinate).not_to have_received(:normalize_selection_range)
      expect(state_store.get(%i[reader selection])).to eq(normalized)
    end

    it 'opens annotation editor when payload requests edit' do
      payload = {
        edit: true,
        annotation: {
          text: 'foo',
          range: { start: 0, end: 1 },
          chapter_index: 3,
        },
      }
      state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: payload))

      handler.apply

      expect(ui_controller).to have_received(:open_annotation_editor_overlay)
        .with(text: 'foo',
              range: { start: 0, end: 1 },
              chapter_index: 3,
              annotation: hash_including(:id, :text))
    end

    it 'clears the pending jump after processing' do
      state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: { chapter_index: 0 }))

      handler.apply

      expect(state_store.get(%i[reader pending_jump])).to be_nil
    end
  end
end
