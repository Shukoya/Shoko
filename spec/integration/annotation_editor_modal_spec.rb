# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Annotation editor modal integration' do
  before do
    mock_terminal

    document_stub = Class.new do
      def initialize(_path, *_args); end

      def load_document
        chapter = Struct.new(:title, :lines).new('Ch1', ['line one', 'line two'])

        Class.new do
          define_method(:initialize) { |ch| @chapter = ch }
          define_method(:chapter_count) { 1 }
          define_method(:chapters) { [@chapter] }
          define_method(:get_chapter) { |_index| @chapter }
          define_method(:title) { 'Doc' }
          define_method(:language) { 'en' }
        end.new(chapter)
      end
    end

    stub_const('EbookReader::Infrastructure::DocumentService', document_stub)
  end

  let(:annotation_service) do
    instance_double('AnnotationService').tap do |svc|
      allow(svc).to receive(:list_for_book).and_return([])
      allow(svc).to receive(:add)
      allow(svc).to receive(:update)
    end
  end

  let(:container) do
    EbookReader::Domain::ContainerFactory.create_default_container.tap do |c|
      c.register(:annotation_service, annotation_service)
    end
  end

  let(:reader) { EbookReader::ReaderController.new('/tmp/fake.epub', nil, container) }
  let(:state) { reader.state }
  let(:ui) { reader.instance_variable_get(:@ui_controller) }
  let(:input) { reader.instance_variable_get(:@input_controller) }
  let(:dispatcher) { input.instance_variable_get(:@dispatcher) }

  let(:selection_range) { { start: { x: 0, y: 0 }, end: { x: 5, y: 0 } } }

  after do
    reader.send(:background_worker)&.shutdown
  end

  def open_editor
    ui.open_annotation_editor_overlay(text: 'Highlighted text', range: selection_range, chapter_index: 0)
  end

  it 'pushes modal mode and routes keys to the overlay session' do
    open_editor

    overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
    expect(overlay).not_to be_nil
    expect(dispatcher.mode_stack.last).to eq(:annotation_editor)
    session = reader.instance_variable_get(:@overlay_session)
    expect(session).not_to be_nil
    expect(session).to be_active

    expect(reader).not_to receive(:quit_to_menu)
    overlay_before = overlay.object_id
    result = input.handle_key('q')
    expect(result).to eq(:handled)
    overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
    current_overlay_note = session.send(:current_overlay).note
    expect(overlay.object_id).to eq(overlay_before)
    expect(current_overlay_note).to eq('q')
    expect(overlay.note).to eq('q')

    input.handle_key('a')
    overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
    expect(overlay.note).to eq('qa')
  end

  it 'saves through the annotation service and restores reader bindings' do
    open_editor

    %w[n o t e].each do |char|
      expect(input.handle_key(char)).to eq(:handled)
    end
    overlay = EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)
    expect(overlay.note).to eq('note')
    session = reader.instance_variable_get(:@overlay_session)
    expect(session).to be_active

    expect(annotation_service).to receive(:add).with(
      reader.path,
      'Highlighted text',
      'note',
      selection_range,
      0,
      nil
    ).and_return(nil)

    input.handle_key("\x13") # Ctrl+S

    expect(EbookReader::Domain::Selectors::ReaderSelectors.annotation_editor_overlay(state)).to be_nil
    expect(dispatcher.mode_stack).to eq([:read])
  end
end
