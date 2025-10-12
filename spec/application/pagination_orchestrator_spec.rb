# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::PaginationOrchestrator do
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:frame_coordinator) { instance_double(EbookReader::Application::FrameCoordinator, render_loading_overlay: nil) }
  let(:dependencies) { instance_double('DependencyContainer') }
  let(:state_store) { EbookReader::Infrastructure::ObserverStateStore.new }
  let(:page_calculator) { instance_double('PageCalculatorService') }
  let(:document) { instance_double('EPUBDocument') }

  subject(:orchestrator) { described_class.new(dependencies) }

  before do
    allow(dependencies).to receive(:resolve).with(:terminal_service).and_return(terminal_service)
    allow(EbookReader::Application::FrameCoordinator).to receive(:new).and_return(frame_coordinator)
  end

  describe '#invalidate_cache' do
    let(:cache) { EbookReader::Infrastructure::PaginationCache }
    let(:key) do
      view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state_store)
      spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state_store)
      EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, view_mode, spacing)
    end

    it 'deletes the cache entry when one exists' do
      allow(cache).to receive(:exists_for_document?).with(document, key).and_return(true)
      allow(cache).to receive(:delete_for_document).with(document, key).and_return(true)

      result = orchestrator.invalidate_cache(document, state_store, width: 80, height: 24)

      expect(result).to eq(:deleted)
    end

    it 'returns :missing when no cache entry exists' do
      allow(cache).to receive(:exists_for_document?).with(document, key).and_return(false)

      result = orchestrator.invalidate_cache(document, state_store, width: 80, height: 24)

      expect(result).to eq(:missing)
    end

    it 'returns :error if deletion fails' do
      allow(cache).to receive(:exists_for_document?).with(document, key).and_return(true)
      allow(cache).to receive(:delete_for_document).and_raise(StandardError.new('boom'))

      result = orchestrator.invalidate_cache(document, state_store, width: 80, height: 24)

      expect(result).to eq(:error)
    end
  end
end
