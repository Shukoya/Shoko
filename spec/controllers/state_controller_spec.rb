# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::StateController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }
  let(:doc) { double('Doc', chapter_count: 3) }
  let(:term) { double('Term', size: [24, 80], cleanup: nil) }
  let(:page_calc) { double('PageCalc', get_page: { chapter_index: 0, start_line: 0 }, build_page_map: nil, find_page_index: 0) }

  class Ctn
    def initialize(term:, page_calc:, ann_svc:, progress_repo:, bookmark_repo:)
      @term = term
      @pc = page_calc
      @ann = ann_svc
      @prog = progress_repo
      @bm = bookmark_repo
    end

    def resolve(name)
      return @term if name == :terminal_service
      return @pc if name == :page_calculator
      return @ann if name == :annotation_service
      return @prog if name == :progress_repository
      return @bm if name == :bookmark_repository
      nil
    end
  end

  let(:annotation_service) { double('AnnotationService', list_for_book: [{ 'text' => 't', 'note' => 'n' }]) }

  let(:progress_repo) do
    double('ProgressRepository', save_for_book: nil,
                                 find_by_book_path: double('Progress', chapter_index: 1, line_offset: 5, timestamp: Time.now.iso8601))
  end

  let(:bookmark_repo) do
    double('BookmarkRepository', find_by_book_path: [{ 'chapter_index' => 1, 'line_offset' => 10 }],
                                 delete_for_book: true,
                                 add_for_book: true)
  end

  subject(:sc) do
    described_class.new(state, doc, '/tmp/book.epub',
                        Ctn.new(term: term, page_calc: page_calc, ann_svc: annotation_service,
                                progress_repo: progress_repo, bookmark_repo: bookmark_repo))
  end

  it 'saves and loads progress (absolute)' do
    state.set(%i[config page_numbering_mode], :absolute)
    state.set(%i[reader current_chapter], 0)
    state.set(%i[reader single_page], 0)
    sc.save_progress
    sc.load_progress
    expect(state.get(%i[reader current_chapter])).to eq(1)
  end

  it 'loads bookmarks into state and can delete' do
    sc.load_bookmarks
    expect(state.get(%i[reader bookmarks])).not_to be_empty
    state.set(%i[reader bookmark_selected], 0)
    expect { sc.delete_selected_bookmark }.not_to raise_error
  end

  it 'refreshes annotations' do
    sc.refresh_annotations
    expect(state.get(%i[reader annotations])).not_to be_empty
  end

  it 'quits to menu and application' do
    sc.quit_to_menu
    expect(state.get(%i[reader running])).to be false
    expect { sc.quit_application }.to raise_error(SystemExit)
  end
end
