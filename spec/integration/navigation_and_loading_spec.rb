# frozen_string_literal: true

require 'rspec'

RSpec.describe 'Navigation and loading integration' do
  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state)     { container.resolve(:global_state) }

  def set_absolute_mode!
    state.update({ %i[config page_numbering_mode] => :absolute,
                   %i[config view_mode] => :single })
  end

  def prime_book_state(chapters:, page_map:)
    state.update({ %i[reader current_chapter] => 0,
                   %i[reader single_page] => 0,
                   %i[reader left_page] => 0,
                   %i[reader right_page] => 1,
                   %i[reader page_map] => page_map,
                   %i[reader total_pages] => page_map.sum,
                   %i[reader total_chapters] => chapters })
  end

  context 'NavigationService in absolute mode' do
    before do
      set_absolute_mode!
      prime_book_state(chapters: 3, page_map: [2, 1, 3])
    end

    it 'advances next_page within a chapter' do
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.next_page
      expect(state.get(%i[reader single_page])).to eq(1)
      expect(state.get(%i[reader current_chapter])).to eq(0)
    end

    it 'rolls over to next chapter at end of chapter' do
      # At terminal page value (page count)
      state.update({ %i[reader single_page] => 2 })
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.next_page
      expect(state.get(%i[reader current_chapter])).to eq(1)
      expect(state.get(%i[reader single_page])).to eq(0)
    end

    it 'goes to previous chapter from first page' do
      state.update({ %i[reader current_chapter] => 1, %i[reader single_page] => 0 })
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.prev_page
      expect(state.get(%i[reader current_chapter])).to eq(0)
      # Service uses page counts as terminal page value (not zero-based index)
      expect(state.get(%i[reader single_page])).to eq(2)
    end

    it 'go_to_end lands on last chapter and last page' do
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.go_to_end
      expect(state.get(%i[reader current_chapter])).to eq(2)
      # Last page equals page count for the chapter (3)
      expect(state.get(%i[reader single_page])).to eq(3)
    end
  end

  context 'ReaderController sets total_chapters from document' do
    class TestDoc3
      def initialize = @chapters = [1, 2, 3]
      def chapter_count = 3
    end

    it 'updates state[:reader][:total_chapters]' do
      # Stub DocumentService to return FakeDoc
      fake_service = instance_double(EbookReader::Infrastructure::DocumentService)
      allow(EbookReader::Infrastructure::DocumentService).to receive(:new).and_return(fake_service)
      allow(fake_service).to receive(:load_document).and_return(TestDoc3.new)

      # Avoid terminal I/O in run; just initialize
      controller = EbookReader::ReaderController.new('fake.epub', nil, container)
      expect(container.resolve(:global_state).get(%i[reader total_chapters])).to eq(3)
      expect(controller.doc).to be_a(TestDoc3)
    end
  end
end
