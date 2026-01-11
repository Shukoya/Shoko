# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::CatalogService do
  let(:scanner) { double('LibraryScanner') }

  it 'adds last_accessed from recent files when listing cached books' do
    cached_repo = double('CachedRepo', list_entries: [{ epub_path: '/tmp/book.epub', title: 'Book' }])
    container = FakeContainer.new(library_scanner: scanner, cached_library_repository: cached_repo)

    allow(Shoko::Adapters::Storage::RecentFiles).to receive(:load).and_return(
      [{ 'path' => '/tmp/book.epub', 'accessed' => '2024-01-01T00:00:00Z' }]
    )

    service = described_class.new(container)
    entries = service.cached_library_entries

    expect(entries.first[:last_accessed]).to eq('2024-01-01T00:00:00Z')
  end

  it 'returns an empty list when cached repository is not available' do
    container = FakeContainer.new(library_scanner: scanner)

    service = described_class.new(container)

    expect(service.cached_library_entries).to eq([])
  end

  it 'returns an empty list when no cached entries exist' do
    cached_repo = double('CachedRepo', list_entries: [])
    container = FakeContainer.new(library_scanner: scanner, cached_library_repository: cached_repo)

    service = described_class.new(container)

    expect(service.cached_library_entries).to eq([])
  end
end
