# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::StateController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }
  let(:doc) { double('Doc', chapter_count: 3) }
  let(:term) { double('Term', size: [24, 80], cleanup: nil) }
  let(:page_calc) { double('PageCalc', get_page: { chapter_index: 0, start_line: 0 }, build_page_map: nil, find_page_index: 0) }

  class Ctn
    def initialize(term, page_calc, ann_svc)
      @term = term
      @pc = page_calc
      @ann = ann_svc
    end

    def resolve(name)
      return @term if name == :terminal_service
      return @pc if name == :page_calculator
      return @ann if name == :annotation_service
      nil
    end
  end

  let(:annotation_service) do
    double('AnnotationService', list_for_book: [{ 'text' => 't', 'note' => 'n' }])
  end

  subject(:sc) { described_class.new(state, doc, '/tmp/book.epub', Ctn.new(term, page_calc, annotation_service)) }

  before do
    stub_const('EbookReader::ProgressManager', Class.new do
      @saved = nil
      class << self; attr_accessor :saved; end
      def self.save(path, ch, off) = @saved = [path, ch, off]
      def self.load(_path) = { 'chapter' => 1, 'line_offset' => 5 }
    end)

    stub_const('EbookReader::BookmarkManager', Class.new do
      def self.get(_path) = [{ 'chapter_index' => 1, 'line_offset' => 10 }]
      def self.delete(_path, _bm); end
    end)

    # Annotation store is no longer used by StateController; using service via DI
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
