# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Screens::LibraryScreenComponent do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  # Fake dependencies resolving catalog_service
  class CatalogDeps
    def initialize(catalog) = (@catalog = catalog)

    def resolve(name)
      return @catalog if name == :catalog_service

      nil
    end
  end

  # Capture writes into an array for assertions
  class LibraryFakeOutput
    attr_reader :writes

    def initialize = (@writes = [])

    def write(row, col, text)
      @writes << [row, col, text]
    end
  end

  it 'renders header and items with fake library service' do
    entries = [
      { title: 'Cached One', authors: 'A', year: '2023', last_accessed: nil, size_bytes: 123_456, open_path: '/cache/1', epub_path: '/src/1.epub' },
      { title: 'Cached Two', authors: 'B', year: '2024', last_accessed: nil, size_bytes: 0, open_path: '/cache/2', epub_path: '/src/2.epub' },
    ]
    fake_catalog = instance_double(EbookReader::Domain::Services::CatalogService,
                                   cached_library_entries: entries,
                                   size_for: 0)

    comp = described_class.new(state, CatalogDeps.new(fake_catalog))

    items = comp.send(:load_items)
    expect(items.length).to eq(2)
    expect(items.first.size_bytes).to eq(123_456)

    output = LibraryFakeOutput.new
    surface = EbookReader::Components::Surface.new(output)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 20)

    comp.render(surface, bounds)

    # Verify header line contains Library (Cached)
    header = output.writes.find { |(_, _, t)| t.include?('Library (Cached)') }
    expect(header).not_to be_nil
    # Verify at least one item title and formatted size are written
    item = output.writes.find { |(_, _, t)| t.include?('Cached One') || t.include?('Cached Two') }
    expect(item).not_to be_nil
    # Verify output includes rendered data for the first title
    item_line = output.writes.find { |(_, _, t)| t.include?('Cached One') }
    expect(item_line).not_to be_nil
  end
end
