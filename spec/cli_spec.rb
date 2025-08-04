# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::CLI do
  let(:main_menu) { instance_double(EbookReader::MainMenu, run: nil) }
  let(:reader) { instance_double(EbookReader::Reader, run: nil) }

  before do
    EbookReader::Infrastructure::Logger.clear
  end

  describe '.run' do
    it 'prints usage and exits with --help' do
      expect(EbookReader::MainMenu).not_to receive(:new)
      expect(EbookReader::Reader).not_to receive(:new)

      expect { described_class.run(['--help']) }
        .to output(/Usage: ebook_reader/).to_stdout
        .and raise_error(SystemExit)
    end

    it 'enables debug logging with --debug' do
      allow(EbookReader::MainMenu).to receive(:new).and_return(main_menu)

      described_class.run(['--debug'])

      expect(EbookReader::Infrastructure::Logger.level).to eq(:debug)
    end

    it 'opens file directly when path provided' do
      expect(EbookReader::Reader).to receive(:new).with('book.epub').and_return(reader)
      expect(reader).to receive(:run)
      expect(EbookReader::MainMenu).not_to receive(:new)

      described_class.run(['book.epub'])
    end

    it 'creates and runs a main menu by default' do
      expect(EbookReader::MainMenu).to receive(:new).and_return(main_menu)
      expect(main_menu).to receive(:run)

      described_class.run([])
    end
  end
end
