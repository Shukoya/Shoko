# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::NavigationController do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }
  let(:doc) { double('Doc', chapters: Array.new(3) { |i| double("Ch#{i}") }) }
  let(:page_manager) { double('PageCalc', total_pages: 20, build_page_map: nil, find_page_index: 0) }
  let(:term) { double('Term', size: [24, 80]) }
  let(:container) do
    Class.new do
      def initialize(term) = @term = term

      def resolve(name)
        name == :terminal_service ? @term : nil
      end
    end.new(term)
  end

  subject(:nav) { described_class.new(state, doc, page_manager, container) }

  it 'advances and retreats page in absolute mode' do
    state.set(%i[config page_numbering_mode], :absolute)
    state.set(%i[reader current_page_index], 0)
    state.set(%i[reader total_pages], 10)
    nav.next_page
    expect(state.get(%i[reader current_page_index])).to eq(1)
    nav.prev_page
    expect(state.get(%i[reader current_page_index])).to eq(0)
  end

  it 'jumps to chapter in dynamic mode and rebuilds map' do
    state.set(%i[config page_numbering_mode], :dynamic)
    nav.jump_to_chapter(1)
    expect(state.get(%i[reader current_chapter])).to eq(1)
  end

  it 'clears selection on navigation' do
    state.set(%i[reader selection], { a: 1 })
    nav.go_to_start
    expect(state.get(%i[reader selection])).to be_nil
  end
end
