# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::CatalogService do
  let(:scanner) { instance_double(EbookReader::Infrastructure::LibraryScanner, epubs: [], cleanup: nil) }
  let(:dependencies) { create_test_dependencies }
  let(:library_service) { instance_double(EbookReader::Domain::Services::LibraryService, list_cached_books: [{ title: 'Cached' }]) }
  subject(:service) { described_class.new(dependencies) }

  before do
    dependencies.register(:library_scanner, scanner)
    dependencies.register(:library_service, library_service)
    allow(scanner).to receive(:load_cached)
  end

  describe '#load_cached' do
    it 'delegates to scanner' do
      expect(scanner).to receive(:load_cached)
      service.load_cached
    end
  end

  describe '#start_scan' do
    it 'delegates with force flag' do
      expect(scanner).to receive(:start_scan).with(force: true)
      service.start_scan(force: true)
    end
  end

  describe '#update_entries' do
    it 'updates scanner entries and clears metadata cache' do
      allow(scanner).to receive(:epubs=)
      service.metadata_for('/tmp/book.epub')
      expect(scanner).to receive(:epubs=).with([{}])
      service.update_entries([{}])
      expect(service.metadata_for('/tmp/book.epub')).to eq({})
    end
  end

  describe '#cached_library_entries' do
    it 'delegates to library service when available' do
      expect(service.cached_library_entries).to eq([{ title: 'Cached' }])
    end
  end

  describe '#metadata_for' do
    it 'caches metadata lookups' do
      allow(EbookReader::Helpers::MetadataExtractor).to receive(:from_epub).with('/tmp/book.epub').and_return(title: 'Test')
      first = service.metadata_for('/tmp/book.epub')
      second = service.metadata_for('/tmp/book.epub')
      expect(first).to eq(title: 'Test')
      expect(second).to equal(first)
    end
  end

  describe '#cleanup' do
    it 'delegates when scanner responds' do
      expect(scanner).to receive(:cleanup)
      service.cleanup
    end
  end
end
