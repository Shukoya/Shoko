# frozen_string_literal: true

require 'rspec'
require 'ebook_reader'
require 'ebook_reader/constants'

RSpec.describe 'Navigation and loading integration' do
  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state)     { container.resolve(:global_state) }
  let(:layout_service) { container.resolve(:layout_service) }

  def set_absolute_mode!
    state.update({ %i[config page_numbering_mode] => :absolute,
                   %i[config view_mode] => :single })
  end

  def prime_book_state(chapters:, page_map:)
    state.update({ %i[reader current_chapter] => 0,
                   %i[reader single_page] => 0,
                   %i[reader left_page] => 0,
                   %i[reader right_page] => lines_for(:split),
                   %i[reader page_map] => page_map,
                   %i[reader total_pages] => page_map.sum,
                   %i[reader total_chapters] => chapters })
  end

  def lines_for(view_mode)
    width  = state.get(%i[ui terminal_width]) || 80
    height = state.get(%i[ui terminal_height]) || 24
    _, content_height = layout_service.calculate_metrics(width, height, view_mode)
    spacing = state.get(%i[config line_spacing]) || EbookReader::Constants::DEFAULT_LINE_SPACING
    layout_service.adjust_for_line_spacing(content_height, spacing)
  end

  context 'NavigationService in absolute mode' do
    before do
      set_absolute_mode!
      state.update({ %i[ui terminal_width] => 100,
                     %i[ui terminal_height] => 30,
                     %i[config line_spacing] => :compact })
      prime_book_state(chapters: 3, page_map: [2, 1, 3])
    end

    let(:single_stride) { lines_for(:single) }

    it 'advances next_page within a chapter' do
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.next_page
      expect(state.get(%i[reader single_page])).to eq(single_stride)
      expect(state.get(%i[reader current_chapter])).to eq(0)
    end

    it 'rolls over to next chapter at end of chapter' do
      # At terminal page value (page count)
      state.update({ %i[reader single_page] => single_stride })
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
      expect(state.get(%i[reader single_page])).to eq(single_stride)
    end

    it 'go_to_end lands on last chapter and last page' do
      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.go_to_end
      expect(state.get(%i[reader current_chapter])).to eq(2)
      expected_offset = (3 - 1) * single_stride
      expect(state.get(%i[reader single_page])).to eq(expected_offset)
    end

    it 'advances split-view pages by column stride' do
      state.update({ %i[config view_mode] => :split,
                     %i[reader left_page] => 0,
                     %i[reader right_page] => lines_for(:split) })

      nav = EbookReader::Domain::Services::NavigationService.new(container)
      nav.next_page

      expect(state.get(%i[reader left_page])).to eq(lines_for(:split))
      expect(state.get(%i[reader right_page])).to eq(lines_for(:split) * 2)
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
