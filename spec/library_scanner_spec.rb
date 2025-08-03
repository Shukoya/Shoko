# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Services::LibraryScanner do
  let(:scanner) { described_class.new }

  describe '#initialize' do
    it 'initializes with empty state' do
      expect(scanner.epubs).to eq([])
      expect(scanner.scan_status).to eq(:idle)
      expect(scanner.scan_message).to eq('')
    end
  end

  describe '#load_cached' do
    before do
      allow(EbookReader::EPUBFinder).to receive(:scan_system).and_return([
                                                                           { 'name' => 'Book 1',
                                                                             'path' => '/book1.epub' },
                                                                         ])
    end

    it 'loads cached epubs' do
      scanner.load_cached
      expect(scanner.epubs.size).to eq(1)
      expect(scanner.scan_status).to eq(:done)
    end

    it 'handles cache load errors' do
      allow(EbookReader::EPUBFinder).to receive(:scan_system).and_raise(StandardError)
      scanner.load_cached

      expect(scanner.scan_status).to eq(:error)
      expect(scanner.epubs).to eq([])
    end
  end

  describe '#start_scan' do
    it 'starts a background scan' do
      allow(Thread).to receive(:new).and_yield
      allow(EbookReader::EPUBFinder).to receive(:scan_system).and_return([])

      scanner.start_scan
      sleep 0.1

      expect(scanner.scan_status).to eq(:scanning)
    end

    it "doesn't start if already scanning" do
      thread = instance_double(Thread, alive?: true)
      scanner.instance_variable_set(:@scan_thread, thread)

      expect(Thread).not_to receive(:new)
      scanner.start_scan
    end
  end

  describe '#process_results' do
    it 'returns nil if queue is empty' do
      expect(scanner.process_results).to be_nil
    end

    it 'processes queued results' do
      queue = scanner.instance_variable_get(:@scan_results_queue)
      queue.push({
                   status: :done,
                   epubs: [{ 'name' => 'Book' }],
                   message: 'Found 1 book',
                 })

      epubs = scanner.process_results
      expect(epubs).to eq([{ 'name' => 'Book' }])
      expect(scanner.scan_status).to eq(:done)
    end
  end

  describe '#cleanup' do
    it 'kills scan thread if alive' do
      thread = instance_double(Thread)
      scanner.instance_variable_set(:@scan_thread, thread)

      expect(thread).to receive(:kill)
      scanner.cleanup
    end
  end
end
