# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::NavigationService do
  let(:state_store) { instance_double(EbookReader::Infrastructure::StateStore) }
  let(:page_calculator) { instance_double(EbookReader::Domain::Services::PageCalculatorService) }
  let(:service) { described_class.new(state_store, page_calculator) }

  before do
    allow(state_store).to receive(:current_state).and_return({
      reader: {
        current_chapter: 0,
        current_page: 0,
        view_mode: :split,
        total_chapters: 5
      }
    })
  end

  describe '#next_page' do
    context 'with single view mode' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { current_chapter: 1, current_page: 5, view_mode: :single }
        })
        allow(page_calculator).to receive(:calculate_pages_for_chapter).and_return(10)
      end

      it 'advances to next page within chapter' do
        expect(state_store).to receive(:set).with([:reader, :current_page], 6)
        
        service.next_page
      end
    end

    context 'with split view mode' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { current_chapter: 1, current_page: 5, view_mode: :split }
        })
        allow(page_calculator).to receive(:calculate_pages_for_chapter).and_return(10)
      end

      it 'advances by 2 pages for split view' do
        expect(state_store).to receive(:set).with([:reader, :current_page], 7)
        
        service.next_page
      end
    end

    context 'at chapter end' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { current_chapter: 1, current_page: 10, view_mode: :single, total_chapters: 5 }
        })
        allow(page_calculator).to receive(:calculate_pages_for_chapter).and_return(10)
      end

      it 'advances to next chapter' do
        expect(state_store).to receive(:update).with({
          [:reader, :current_chapter] => 2,
          [:reader, :current_page] => 0
        })
        
        service.next_page
      end
    end
  end

  describe '#prev_page' do
    context 'with single view mode' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { current_chapter: 1, current_page: 5, view_mode: :single }
        })
      end

      it 'goes back to previous page' do
        expect(state_store).to receive(:set).with([:reader, :current_page], 4)
        
        service.prev_page
      end
    end

    context 'at chapter beginning' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { current_chapter: 2, current_page: 0, view_mode: :single }
        })
        allow(page_calculator).to receive(:calculate_pages_for_chapter).with(1).and_return(15)
      end

      it 'goes to previous chapter last page' do
        expect(state_store).to receive(:update).with({
          [:reader, :current_chapter] => 1,
          [:reader, :current_page] => 15
        })
        
        service.prev_page
      end
    end
  end

  describe '#jump_to_chapter' do
    it 'jumps to specified chapter' do
      expect(state_store).to receive(:update).with({
        [:reader, :current_chapter] => 3,
        [:reader, :current_page] => 0
      })
      
      service.jump_to_chapter(3)
    end

    it 'validates chapter index' do
      expect {
        service.jump_to_chapter(-1)
      }.to raise_error(ArgumentError, 'Chapter index must be non-negative')
    end

    context 'when chapter index exceeds total chapters' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { total_chapters: 3 }
        })
      end

      it 'raises error for invalid chapter index' do
        expect {
          service.jump_to_chapter(5)
        }.to raise_error(ArgumentError, /Chapter index 5 exceeds total chapters 3/)
      end
    end
  end

  describe '#go_to_start' do
    it 'goes to beginning of book' do
      expect(state_store).to receive(:update).with({
        [:reader, :current_chapter] => 0,
        [:reader, :current_page] => 0
      })
      
      service.go_to_start
    end
  end

  describe '#go_to_end' do
    before do
      allow(state_store).to receive(:current_state).and_return({
        reader: { total_chapters: 5 }
      })
      allow(page_calculator).to receive(:calculate_pages_for_chapter).with(4).and_return(20)
    end

    it 'goes to end of book' do
      expect(state_store).to receive(:update).with({
        [:reader, :current_chapter] => 4,
        [:reader, :current_page] => 20
      })
      
      service.go_to_end
    end

    context 'when no chapters available' do
      before do
        allow(state_store).to receive(:current_state).and_return({
          reader: { total_chapters: 0 }
        })
      end

      it 'does nothing' do
        expect(state_store).not_to receive(:update)
        
        service.go_to_end
      end
    end
  end

  describe '#scroll' do
    before do
      allow(state_store).to receive(:current_state).and_return({
        reader: { current_page: 5 }
      })
      allow(page_calculator).to receive(:calculate_pages_for_chapter).and_return(10)
    end

    it 'scrolls up by specified lines' do
      expect(state_store).to receive(:set).with([:reader, :current_page], 3)
      
      service.scroll(:up, 2)
    end

    it 'scrolls down by specified lines' do
      expect(state_store).to receive(:set).with([:reader, :current_page], 7)
      
      service.scroll(:down, 2)
    end

    it 'prevents scrolling above beginning' do
      allow(state_store).to receive(:current_state).and_return({
        reader: { current_page: 1 }
      })
      
      expect(state_store).to receive(:set).with([:reader, :current_page], 0)
      
      service.scroll(:up, 5)
    end

    it 'prevents scrolling beyond end' do
      expect(state_store).to receive(:set).with([:reader, :current_page], 10)
      
      service.scroll(:down, 10)
    end

    it 'validates scroll direction' do
      expect {
        service.scroll(:invalid, 1)
      }.to raise_error(ArgumentError, 'Invalid scroll direction: invalid')
    end
  end
end