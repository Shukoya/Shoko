# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader'

RSpec.describe EbookReader::Domain::Services::NavigationService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state) { container.resolve(:global_state) }
  let(:service) { container.resolve(:navigation_service) }
  let(:layout_service) { container.resolve(:layout_service) }

  before do
    state.reset!
    state.update({
                   %i[config page_numbering_mode] => :absolute,
                   %i[config line_spacing] => :compact,
                   %i[config view_mode] => :single,
                   %i[ui terminal_width] => 100,
                   %i[ui terminal_height] => 30,
                   %i[reader current_chapter] => 0,
                   %i[reader current_page] => 0,
                   %i[reader single_page] => 0,
                   %i[reader left_page] => 0,
                   %i[reader right_page] => lines_for(:split),
                   %i[reader page_map] => [2, 1, 3],
                   %i[reader total_pages] => 6,
                   %i[reader total_chapters] => 3,
                 })
  end

  def lines_for(view_mode)
    width = state.get(%i[ui terminal_width])
    height = state.get(%i[ui terminal_height])
    _, content_height = layout_service.calculate_metrics(width, height, view_mode)
    spacing = state.get(%i[config line_spacing])
    layout_service.adjust_for_line_spacing(content_height, spacing)
  end

  describe '#next_page' do
    context 'single view mode' do
      before { state.update({ %i[config view_mode] => :single }) }

      it 'advances by one full page stride' do
        stride = lines_for(:single)
        service.next_page
        expect(state.get(%i[reader single_page])).to eq(stride)
        expect(state.get(%i[reader current_page])).to eq(stride)
      end

      it 'advances to next chapter at the last page' do
        stride = lines_for(:single)
        state.update({ %i[reader current_chapter] => 0,
                       %i[reader single_page] => stride,
                       %i[reader current_page] => stride })
        service.next_page
        expect(state.get(%i[reader current_chapter])).to eq(1)
        expect(state.get(%i[reader single_page])).to eq(0)
      end
    end

    context 'split view mode' do
      before { state.update({ %i[config view_mode] => :split }) }

      it 'advances both columns by the column stride' do
        stride = lines_for(:split)
        service.next_page
        expect(state.get(%i[reader left_page])).to eq(stride)
        expect(state.get(%i[reader right_page])).to eq(stride * 2)
        expect(state.get(%i[reader current_page])).to eq(stride)
      end
    end
  end

  describe '#prev_page' do
    context 'single view mode' do
      before do
        state.update({ %i[config view_mode] => :single,
                       %i[reader single_page] => lines_for(:single),
                       %i[reader current_page] => lines_for(:single) })
      end

      it 'moves back by one stride' do
        service.prev_page
        expect(state.get(%i[reader single_page])).to eq(0)
        expect(state.get(%i[reader current_page])).to eq(0)
      end
    end

    context 'at chapter beginning' do
      before do
        state.update({ %i[config view_mode] => :single,
                       %i[reader current_chapter] => 1,
                       %i[reader single_page] => 0,
                       %i[reader current_page] => 0 })
      end

      it 'wraps to the previous chapter last page' do
        stride = lines_for(:single)
        service.prev_page
        expect(state.get(%i[reader current_chapter])).to eq(0)
        expect(state.get(%i[reader single_page])).to eq(stride)
      end
    end
  end

  describe '#jump_to_chapter' do
    it 'positions at the requested chapter start' do
      service.jump_to_chapter(2)
      expect(state.get(%i[reader current_chapter])).to eq(2)
      expect(state.get(%i[reader single_page])).to eq(0)
    end

    it 'validates negative indices' do
      expect { service.jump_to_chapter(-1) }.to raise_error(ArgumentError)
    end

    it 'validates indices beyond chapter count' do
      expect { service.jump_to_chapter(10) }.to raise_error(ArgumentError)
    end
  end

  describe '#go_to_start' do
    it 'resets chapter and offsets' do
      state.update({ %i[reader current_chapter] => 2,
                     %i[reader single_page] => 10,
                     %i[reader current_page] => 10 })
      service.go_to_start
      expect(state.get(%i[reader current_chapter])).to eq(0)
      expect(state.get(%i[reader current_page])).to eq(0)
      expect(state.get(%i[reader single_page])).to eq(0)
    end
  end

  describe '#go_to_end' do
    it 'positions at the last chapter final offset' do
      service.go_to_end
      stride = lines_for(:single)
      expect(state.get(%i[reader current_chapter])).to eq(2)
      expect(state.get(%i[reader single_page])).to eq(stride * 2)
    end

    it 'does nothing when no chapters exist' do
      state.update({ %i[reader total_chapters] => 0,
                     %i[reader page_map] => [] })
      expect { service.go_to_end }.not_to(change { state.get(%i[reader current_chapter]) })
    end
  end

  describe '#scroll' do
    before { state.update({ %i[config view_mode] => :single }) }

    it 'scrolls up within chapter bounds' do
      state.update({ %i[reader single_page] => 10,
                     %i[reader current_page] => 10 })
      service.scroll(:up, 4)
      expect(state.get(%i[reader single_page])).to eq(6)
    end

    it 'scrolls down within chapter bounds' do
      service.scroll(:down, 3)
      expect(state.get(%i[reader single_page])).to eq(3)
    end

    it 'limits scrolling beyond the chapter end' do
      service.scroll(:down, 100)
      stride = lines_for(:single)
      expect(state.get(%i[reader single_page])).to eq(stride)
    end

    it 'prevents scrolling before chapter start' do
      service.scroll(:up, 5)
      expect(state.get(%i[reader single_page])).to eq(0)
    end

    it 'validates direction' do
      expect { service.scroll(:sideways, 1) }.to raise_error(ArgumentError)
    end
  end
end
