# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Annotation lifecycle integration', fake_fs: true do
  let(:epub_path) { '/book.epub' }
  let(:config) do
    instance_double(EbookReader::Config,
                    view_mode: :single,
                    page_numbering_mode: :absolute,
                    line_spacing: :normal,
                    highlight_quotes: false,
                    show_page_numbers: false)
  end
  let(:chapter) do
    EbookReader::Models::Chapter.new(number: '1', title: 'Ch1', lines: ['Sample line of text'], metadata: nil)
  end
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Test',
                    chapters: [chapter],
                    chapter_count: 1,
                    language: 'en')
  end

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter).and_return(chapter)
    allow(EbookReader::BookmarkManager).to receive(:get).and_return([])
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
    allow(EbookReader::ProgressManager).to receive(:save)
    allow_any_instance_of(EbookReader::Reader).to receive(:set_message)
  end

  it 'allows creating, updating, and deleting annotations with persistence' do
    reader = EbookReader::Reader.new(epub_path, config)
    allow(reader).to receive(:extract_selected_text).and_return('selected text')

    # Simulate selecting text and choosing Create Annotation from popup menu
    reader.handle_mouse_input("\e[<0;11;5M")   # press at (10,4)
    reader.handle_mouse_input("\e[<32;15;5M")  # drag to (14,4)
    reader.handle_mouse_input("\e[<0;15;5m")   # release to finish selection
    menu = reader.instance_variable_get(:@popup_menu)
    expect(menu).not_to be_nil
    expect(menu.visible).to be true
    reader.handle_mouse_input("\e[<0;16;6m")   # click first menu item

    editor = reader.instance_variable_get(:@current_mode)
    expect(editor).to be_a(EbookReader::ReaderModes::AnnotationEditorMode)

    %w[N o t e].each { |ch| editor.handle_input(ch) }
    editor.handle_input("\x13") # Ctrl+S save

    annotations = EbookReader::Annotations::AnnotationStore.get(epub_path)
    expect(annotations.length).to eq(1)
    expect(annotations.first['note']).to eq('Note')

    # Reload reader to verify persistence and perform update
    reader2 = EbookReader::Reader.new(epub_path, config)
    reader2.switch_mode(:annotations)
    list_mode = reader2.instance_variable_get(:@current_mode)
    expect(list_mode.instance_variable_get(:@annotations).length).to eq(1)

    list_mode.handle_input("\r")
    editor2 = reader2.instance_variable_get(:@current_mode)
    editor2.handle_input('!')
    editor2.handle_input("\x13")
    annotations = EbookReader::Annotations::AnnotationStore.get(epub_path)
    expect(annotations.first['note']).to eq('Note!')

    # Delete annotation
    reader2.switch_mode(:annotations)
    list_mode = reader2.instance_variable_get(:@current_mode)
    list_mode.handle_input('d')
    expect(EbookReader::Annotations::AnnotationStore.get(epub_path)).to be_empty

    # Reload to confirm deletion persisted
    reader3 = EbookReader::Reader.new(epub_path, config)
    reader3.switch_mode(:annotations)
    list_mode = reader3.instance_variable_get(:@current_mode)
    expect(list_mode.instance_variable_get(:@annotations)).to be_empty
  end
end
