# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Screens::LibraryScreenComponent do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  # Fake dependencies resolving library_service
  class LibraryDeps
    def initialize(ls) = (@ls = ls)

    def resolve(name)
      return @ls if name == :library_service

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
    fake_ls = double('LibraryService', list_cached_books: [
                       { title: 'Cached One', authors: 'A', year: '2023', last_accessed: nil, size_bytes: 123, open_path: '/cache/1', epub_path: '/src/1.epub' },
                       { title: 'Cached Two', authors: 'B', year: '2024', last_accessed: nil, size_bytes: 456, open_path: '/cache/2', epub_path: '/src/2.epub' },
                     ])
    comp = described_class.new(state, LibraryDeps.new(fake_ls))

    output = LibraryFakeOutput.new
    surface = EbookReader::Components::Surface.new(output)
    bounds = EbookReader::Components::Rect.new(x: 1, y: 1, width: 80, height: 20)

    comp.render(surface, bounds)

    # Verify header line contains Library (Cached)
    header = output.writes.find { |(_, _, t)| t.include?('Library (Cached)') }
    expect(header).not_to be_nil
    # Verify at least one item title is written
    item = output.writes.find { |(_, _, t)| t.include?('Cached One') || t.include?('Cached Two') }
    expect(item).not_to be_nil
  end
end
