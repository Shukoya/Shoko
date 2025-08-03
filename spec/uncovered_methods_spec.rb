# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uncovered Methods' do
  describe EbookReader::Helpers::ReaderHelpers do
    let(:helper) { Class.new { include EbookReader::Helpers::ReaderHelpers }.new }

    it 'handles wrap_line with nil word edge case' do
      lines = ['word1 word2']
      allow(lines.first).to receive(:split).and_return(['word1', nil, 'word2'])

      result = helper.wrap_lines(lines, 20)
      expect(result).to be_an(Array)
    end

    it 'handles wrap_lines with mixed empty and whitespace lines' do
      lines = ['', '   ', "\t\t", 'actual text', "  \n  "]
      result = helper.wrap_lines(lines, 50)

      expect(result).to include('')
      expect(result).to include('actual text')
    end
  end

  describe EbookReader::UI::Screens::BrowseScreen do
    let(:screen) { described_class.new(EbookReader::Services::LibraryScanner.new) }

    before do
      allow(EbookReader::Terminal).to receive(:write)
    end

    it 'renders all status types' do
      screen.render_status(:idle, '')
      screen.render_status(:scanning, 'Scanning...')
      screen.render_status(:error, 'Error!')
      screen.render_status(:done, 'Complete')
      screen.render_status(:unknown, 'Unknown')
    end
  end

  describe EbookReader::Terminal::ANSI do
    it 'has all color constants defined' do
      expect(described_class::BLACK).to eq("\e[30m")
      expect(described_class::MAGENTA).to eq("\e[35m")
      expect(described_class::GRAY).to eq("\e[90m")
    end
  end

  describe EbookReader::Constants do
    it 'has proper skip directories' do
      expect(described_class::SKIP_DIRS).to include('node_modules')
      expect(described_class::SKIP_DIRS).to include('.git')
      expect(described_class::SKIP_DIRS.size).to be > 10
    end
  end
end
