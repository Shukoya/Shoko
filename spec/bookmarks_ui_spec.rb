# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Concerns::BookmarksUI do
  let(:doc) { double('doc', get_chapter: double('chapter', title: 'Ch1')) }
  let(:dummy_class) do
    Class.new do
      include EbookReader::Concerns::BookmarksUI
      include EbookReader::Constants::UIConstants

      attr_accessor :bookmarks, :bookmark_selected

      def initialize(doc, bookmarks)
        @doc = doc
        @bookmarks = bookmarks
        @bookmark_selected = 0
      end
    end
  end

  let(:bookmarks) do
    [
      EbookReader::Models::Bookmark.new(chapter_index: 0, line_offset: 10, text_snippet: 'First',
                                        created_at: Time.now),
      EbookReader::Models::Bookmark.new(chapter_index: 1, line_offset: 20, text_snippet: 'Second',
                                        created_at: Time.now),
    ]
  end

  subject(:ui) { dummy_class.new(doc, bookmarks) }

  before do
    allow(EbookReader::Terminal).to receive(:write)
    stub_const('EbookReader::Concerns::BookmarksUI::MIN_COLUMN_WIDTH',
               EbookReader::Constants::UIConstants::MIN_COLUMN_WIDTH)
  end

  it 'draws full screen with bookmarks' do
    ui.draw_bookmarks_screen(24, 80)
    expect(EbookReader::Terminal).to have_received(:write).at_least(5).times
  end

  it 'draws empty state' do
    empty = dummy_class.new(doc, [])
    empty.draw_bookmarks_screen(24, 80)
    expect(EbookReader::Terminal).to have_received(:write).at_least(2).times
  end

  it 'calculates visible range' do
    ui.bookmark_selected = 1
    range = ui.calculate_bookmark_visible_range(2)
    expect(range).to eq(0...2)
  end

  it 'renders selected bookmark item' do
    context = EbookReader::Models::BookmarkDrawingContext.new(
      bookmark: bookmarks.first,
      chapter_title: 'Ch1',
      index: 0,
      position: EbookReader::Models::Position.new(row: 4, col: 2),
      width: 80
    )
    ui.draw_bookmark_item(context)
    expect(EbookReader::Terminal).to have_received(:write).at_least(3).times
  end

  it 'renders unselected bookmark item' do
    context = EbookReader::Models::BookmarkDrawingContext.new(
      bookmark: bookmarks.last,
      chapter_title: 'Ch1',
      index: 1,
      position: EbookReader::Models::Position.new(row: 6, col: 2),
      width: 80
    )
    ui.draw_bookmark_item(context)
    expect(EbookReader::Terminal).to have_received(:write).at_least(2).times
  end

  it 'draws footer' do
    ui.draw_bookmarks_footer(24)
    expect(EbookReader::Terminal).to have_received(:write).with(23, anything, /Navigate/)
  end
end
