# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Refactoring Integration' do
  context 'new infrastructure components' do
    describe EbookReader::Infrastructure::Logger do
      it 'logs messages without crashing' do
        expect { described_class.info('Test message') }.not_to raise_error
      end

      it 'respects log levels' do
        described_class.level = :error
        expect { described_class.debug('Debug') }.not_to output.to_stderr
        expect { described_class.error('Error') }.to output.to_stderr
      end
    end

    describe EbookReader::Infrastructure::Validator do
      let(:validator) { described_class.new }

      it 'validates presence' do
        expect(validator.presence_valid?('', :field)).to be false
        expect(validator.presence_valid?('value', :field)).to be true
      end
    end

    describe EbookReader::Infrastructure::PerformanceMonitor do
      it 'times operations' do
        result = described_class.time('test') { 1 + 1 }
        expect(result).to eq(2)
        expect(described_class.stats('test')).not_to be_nil
      end
    end
  end

  context 'validators' do
    describe EbookReader::Validators::FilePathValidator do
      let(:validator) { described_class.new }

      it 'validates EPUB files' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:readable?).and_return(true)
        allow(File).to receive(:size).and_return(1000)

        expect(validator.validate?('/test.epub')).to be true
        expect(validator.validate?('/test.txt')).to be false
      end
    end

    describe EbookReader::Validators::TerminalSizeValidator do
      let(:validator) { described_class.new }

      it 'validates terminal dimensions' do
        expect(validator.validate?(80, 24)).to be true
        expect(validator.validate?(10, 5)).to be false
      end
    end
  end

  context 'core components' do
    describe EbookReader::Core::ReaderState do
      let(:state) { described_class.new }

      it 'manages reader state' do
        expect(state.current_chapter).to eq(0)
        state.current_chapter = 5
        expect(state.current_chapter).to eq(5)
      end

      it 'creates and restores snapshots' do
        state.current_chapter = 3
        snapshot = state.to_h

        new_state = described_class.new
        new_state.restore_from(snapshot)
        expect(new_state.current_chapter).to eq(3)
      end
    end
  end
end
