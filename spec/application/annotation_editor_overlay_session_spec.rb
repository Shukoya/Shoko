# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/application/annotation_editor_overlay_session'
require 'ebook_reader/components/annotation_editor_overlay_component'
require 'ebook_reader/infrastructure/event_bus'
require 'ebook_reader/infrastructure/observer_state_store'
require 'ebook_reader/domain/actions/update_annotation_editor_overlay_action'
require 'ebook_reader/domain/actions/update_selection_action'
require 'ebook_reader/domain/selectors/reader_selectors'

RSpec.describe EbookReader::Application::AnnotationEditorOverlaySession do
  class StubUIController
    attr_accessor :current_book_path
    attr_reader :messages, :closed_count, :refreshed, :current_book_path

    def initialize(state)
      @state = state
      @messages = []
      @closed_count = 0
      @refreshed = 0
    end

    def set_message(text, _duration = nil)
      @messages << text
    end

    def refresh_annotations
      @refreshed += 1
    end

    def close_annotation_editor_overlay
      overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
      overlay&.hide if overlay.respond_to?(:hide)
      @state.dispatch(EbookReader::Domain::Actions::ClearAnnotationEditorOverlayAction.new)
      @closed_count += 1
    end

    def activate_annotation_editor_overlay_session; end

    def deactivate_annotation_editor_overlay_session; end
  end

  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:ui_controller) { StubUIController.new(state) }
  let(:annotation_service) { instance_double('AnnotationService') }
  let(:dependencies) do
    Class.new do
      def initialize(service)
        @service = service
      end

      def resolve(key)
        raise ArgumentError, "Unknown dependency: #{key}" unless key == :annotation_service

        @service
      end
    end.new(annotation_service)
  end
  let(:session) { described_class.new(state, dependencies, ui_controller) }
  let(:range) { { start: { x: 0, y: 0 }, end: { x: 5, y: 0 } } }

  before do
    ui_controller.current_book_path = '/books/test.epub'
    allow(annotation_service).to receive(:add)
    allow(annotation_service).to receive(:update)
    allow(annotation_service).to receive(:list_for_book).and_return([])
  end

  def overlay_from_state
    EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
  end

  def build_overlay(annotation: nil)
    EbookReader::Components::AnnotationEditorOverlayComponent.new(
      selected_text: 'sample text',
      range: range,
      chapter_index: 0,
      annotation: annotation
    )
  end

  describe '#handle_character' do
    it 'appends printable characters to the overlay note' do
      overlay = build_overlay
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))

      session.handle_character('a')
      expect(overlay.note).to eq('a')
    end
  end

  describe '#handle_backspace' do
    it 'removes the last character' do
      overlay = build_overlay
      overlay.handle_character('a')
      overlay.handle_character('b')
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))

      session.handle_backspace
      expect(overlay.note).to eq('a')
    end
  end

  describe '#handle_enter' do
    it 'inserts a newline' do
      overlay = build_overlay
      overlay.handle_character('a')
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))

      session.handle_enter
      expect(overlay.note).to eq("a\n")
    end
  end

  describe '#save_annotation' do
    it 'adds a new annotation and clears overlay state' do
      overlay = build_overlay
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))

      expect(annotation_service).to receive(:add).with('/books/test.epub',
                                                       'sample text',
                                                       '',
                                                       range,
                                                       0,
                                                       nil)
      expect(annotation_service).not_to receive(:update)

      session.save_annotation

      expect(ui_controller.messages.last).to eq('Annotation saved!')
      expect(ui_controller.closed_count).to eq(1)
      expect(overlay_from_state).to be_nil
    end

    it 'updates an existing annotation' do
      overlay = build_overlay(annotation: { 'id' => 42, 'note' => 'existing', 'text' => 'sample text', 'range' => range, 'chapter_index' => 0 })
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))

      expect(annotation_service).to receive(:update).with('/books/test.epub', 42, 'existing')
      expect(annotation_service).not_to receive(:add)

      session.save_annotation

      expect(ui_controller.messages.last).to eq('Annotation updated')
      expect(ui_controller.closed_count).to eq(1)
    end
  end

  describe '#cancel_annotation' do
    it 'clears the overlay and selection with feedback' do
      overlay = build_overlay
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))
      state.dispatch(EbookReader::Domain::Actions::UpdateSelectionAction.new(range))

      session.cancel_annotation

      expect(ui_controller.messages.last).to eq('Annotation cancelled')
      expect(overlay_from_state).to be_nil
      expect(state.get(%i[reader selection])).to be_nil
    end
  end

  describe '#active?' do
    it 'reflects overlay visibility' do
      overlay = build_overlay
      state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationEditorOverlayAction.new(overlay))
      expect(session).to be_active

      session.save_annotation
      expect(session).not_to be_active
    end
  end
end
