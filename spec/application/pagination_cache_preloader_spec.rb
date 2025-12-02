# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::PaginationCachePreloader do
  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state_store) { EbookReader::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:page_calculator) do
    instance_double('PageCalculatorService',
                    hydrate_from_cache: true,
                    apply_pending_precise_restore!: nil)
  end
  let(:pagination_cache) do
    double('PaginationCache',
           layout_key: '80x24_split_compact',
           exists_for_document?: true,
           parse_layout_key: nil,
           layout_keys_for_document: [],
           load_for_document: cached_pages)
  end
  let(:preloader) do
    described_class.new(state: state_store,
                        page_calculator: page_calculator,
                        pagination_cache: pagination_cache)
  end
  let(:doc) { double('Document') }
  let(:cached_pages) do
    [
      { chapter_index: 0, start_line: 0, end_line: 9, page_in_chapter: 0, total_pages_in_chapter: 1 },
    ]
  end

  it 'hydrates from cached pagination without rebuilding maps' do
    result = preloader.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:hit)
    expect(page_calculator).to have_received(:hydrate_from_cache).with(cached_pages,
                                                                       state: state_store,
                                                                       width: 80,
                                                                       height: 24)
  end
end
