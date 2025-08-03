# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Utilities comprehensive' do
  describe EbookReader::Services::LibraryScanner do
    let(:scanner) { described_class.new }

    it 'handles scan thread cleanup when thread is nil' do
      scanner.instance_variable_set(:@scan_thread, nil)
      expect { scanner.cleanup }.not_to raise_error
    end

    it 'handles scan thread cleanup when thread is dead' do
      thread = instance_double(Thread, alive?: false)
      scanner.instance_variable_set(:@scan_thread, thread)
      expect(thread).not_to receive(:kill)
      scanner.cleanup
    end
  end

  describe EbookReader::Config do
    it 'handles nil values in config data gracefully' do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('{"view_mode":null,"theme":null}')

      config = described_class.new
      expect(config.view_mode).to eq(:split) # Uses default
      expect(config.theme).to eq(:dark) # Uses default
    end

    it 'handles numeric boolean values' do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('{"show_page_numbers":1,"highlight_quotes":0}')

      config = described_class.new
      expect(config.show_page_numbers).to be true
      expect(config.highlight_quotes).to be true # Falls back to default
    end
  end

  describe EbookReader::EPUBFinder do
    it 'handles cache timestamp parsing errors' do
      allow(File).to receive(:exist?).with(described_class::CACHE_FILE).and_return(true)
      allow(File).to receive(:read).and_return('{"timestamp":"invalid","files":[]}')

      result = described_class.scan_system
      expect(result).to be_an(Array)
    end

    it 'handles interrupted directory scanning' do
      allow(Dir).to receive(:exist?).and_return(true)
      allow(Dir).to receive(:entries).and_raise(Errno::EINTR)

      result = described_class.scan_system(force_refresh: true)
      expect(result).to be_an(Array)
    end
  end
end
