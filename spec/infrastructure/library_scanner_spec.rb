# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::LibraryScanner do
  subject(:scanner) { described_class.new }

  describe '#load_cached' do
    it 'loads cached entries using EPUBFinder without forcing a rescan' do
      entries = [{ 'path' => '/books/a.epub' }]
      expect(EbookReader::EPUBFinder).to receive(:scan_system)
        .with(force_refresh: false)
        .and_return(entries)

      scanner.load_cached

      expect(scanner.epubs).to eq(entries)
      expect(scanner.scan_status).to eq(:done)
      expect(scanner.scan_message).to eq('Loaded 1 books from cache')
    end

    it 'falls back to empty state when the finder raises' do
      allow(EbookReader::EPUBFinder).to receive(:scan_system)
        .with(force_refresh: false)
        .and_raise(StandardError, 'boom')

      scanner.load_cached

      expect(scanner.epubs).to eq([])
      expect(scanner.scan_status).to eq(:error)
      expect(scanner.scan_message).to include('boom')
    end
  end
end
