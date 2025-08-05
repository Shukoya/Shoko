# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Text selection highlighting', fake_fs: true do
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
    EbookReader::Models::Chapter.new(number: '1', title: 'Ch1',
                                     lines: ['Sample line of text'],
                                     metadata: nil)
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

    @reader = EbookReader::Reader.new(epub_path, config)
    @reader.draw_screen
    allow(EbookReader::Terminal).to receive(:write)
  end

  it 'highlights selection immediately and shows popup menu' do
    # Start selection and verify highlight
    @reader.handle_mouse_input("\e[<0;11;13M")
    expect(EbookReader::Terminal).to have_received(:write).with(
      anything, anything,
      a_string_including(EbookReader::Terminal::ANSI::BG_BRIGHT_GREEN)
    )

    # Drag selection further and ensure highlight updates
    @reader.handle_mouse_input("\e[<32;15;13M")
    expect(EbookReader::Terminal).to have_received(:write).with(
      anything, anything,
      a_string_including(EbookReader::Terminal::ANSI::BG_BRIGHT_GREEN)
    ).at_least(:twice)

    # Release to display popup menu
    @reader.handle_mouse_input("\e[<0;15;13m")
    menu = @reader.instance_variable_get(:@popup_menu)
    expect(menu).not_to be_nil
    expect(menu.visible).to be true
  end
end
