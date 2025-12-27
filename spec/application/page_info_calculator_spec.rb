# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::PageInfoCalculator do
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new }
  let(:doc) { instance_double('EPUBDocument') }
  let(:page_calculator) { instance_double('PageCalculatorService', total_pages: 12) }
  let(:layout_service) { instance_double('LayoutService') }
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:orchestrator) { instance_double('PaginationOrchestrator') }

  let(:dependencies) do
    described_class::Dependencies.new(
      state: state,
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_orchestrator: orchestrator
    )
  end

  def build_calculator(defer_page_map: false)
    described_class.new(dependencies: dependencies, defer_page_map: defer_page_map)
  end

  before do
    allow(layout_service).to receive(:adjust_for_line_spacing) { |height, _| height }
    allow(layout_service).to receive(:calculate_metrics) { |_w, _h, _mode| [0, 20] }
    allow(orchestrator).to receive(:build_full_map!)
    allow(page_calculator).to receive(:build_dynamic_map!)
    allow(page_calculator).to receive(:apply_pending_precise_restore!)
    allow(page_calculator).to receive(:build_absolute_map!).and_return([5, 5])
  end

  describe '#calculate' do
    context 'when dynamic mode and single view' do
      it 'returns current/total pages using the calculator' do
        state.update({
                       %i[config page_numbering_mode] => :dynamic,
                       %i[config view_mode] => :single,
                       %i[reader current_page_index] => 4,
                     })
        allow(page_calculator).to receive(:total_pages).and_return(9)

        expect(build_calculator.calculate).to eq(type: :single, current: 5, total: 9)
      end
    end

    context 'when dynamic mode and split view' do
      it 'returns left/right page metadata' do
        state.update({
                       %i[config page_numbering_mode] => :dynamic,
                       %i[config view_mode] => :split,
                       %i[reader current_page_index] => 2,
                     })
        allow(page_calculator).to receive(:total_pages).and_return(6)

        result = build_calculator.calculate

        expect(result).to eq(
          type: :split,
          left: { current: 3, total: 6 },
          right: { current: 4, total: 6 }
        )
      end
    end

    context 'when absolute mode and single view' do
      it 'derives page numbers from page map and offsets' do
        state.update({
                       %i[config page_numbering_mode] => :absolute,
                       %i[config view_mode] => :single,
                       %i[reader current_chapter] => 1,
                       %i[reader single_page] => 20,
                       %i[reader page_map] => [5, 5, 5],
                       %i[reader total_pages] => 12,
                     })

        expect(build_calculator(defer_page_map: true).calculate).to eq(
          type: :single,
          current: 7,
          total: 12
        )
      end
    end

    context 'when absolute mode and split view' do
      it 'returns split page info for both columns' do
        state.update({
                       %i[config page_numbering_mode] => :absolute,
                       %i[config view_mode] => :split,
                       %i[reader current_chapter] => 0,
                       %i[reader left_page] => 0,
                       %i[reader right_page] => 20,
                       %i[reader page_map] => [10],
                       %i[reader total_pages] => 10,
                     })

        expect(build_calculator(defer_page_map: true).calculate).to eq(
          type: :split,
          left: { current: 1, total: 10 },
          right: { current: 2, total: 10 }
        )
      end
    end

    it 'returns zeroed info when page numbers are hidden' do
      state.update(%i[config show_page_numbers] => false)

      expect(build_calculator.calculate).to eq(type: :single, current: 0, total: 0)
    end

    it 'builds absolute map via orchestrator when needed' do
      state.update({
                     %i[config page_numbering_mode] => :absolute,
                     %i[config view_mode] => :single,
                     %i[reader single_page] => 0,
                     %i[reader current_chapter] => 0,
                     %i[reader total_pages] => 0,
                   })

      allow(orchestrator).to receive(:build_full_map!) do
        state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                         page_map: [5],
                         total_pages: 5
                       ))
      end

      result = build_calculator.calculate

      expect(orchestrator).to have_received(:build_full_map!)
      expect(result).to eq(type: :single, current: 1, total: 5)
    end
  end
end
