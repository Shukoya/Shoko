# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::Screens::BrowseScreen do
  let(:browse_screen) { described_class.new(EbookReader::Services::LibraryScanner.new) }

  before do
    allow(EbookReader::Terminal).to receive(:write)
  end

  describe '#render_header' do
    it 'renders header with title and controls' do
      expect(EbookReader::Terminal).to receive(:write).with(1, 2, /Browse Books/)
      expect(EbookReader::Terminal).to receive(:write).with(1, anything, /Refresh.*Back/)

      browse_screen.render_header(80)
    end
  end

  describe '#render_search_bar' do
    it 'renders search input' do
      expect(EbookReader::Terminal).to receive(:write).with(3, 2, /Search:/)
      expect(EbookReader::Terminal).to receive(:write).with(3, 10, /test_query_/)

      browse_screen.render_search_bar('test_query', 'test_query'.length)
    end
  end

  describe '#render_status' do
    it 'renders scanning status' do
      expect(EbookReader::Terminal).to receive(:write).with(4, 2, /Scanning/)
      browse_screen.render_status(:scanning, 'Scanning for files...')
    end

    it 'renders error status' do
      expect(EbookReader::Terminal).to receive(:write).with(4, 2, /Error/)
      browse_screen.render_status(:error, 'Error occurred')
    end

    it 'renders done status' do
      expect(EbookReader::Terminal).to receive(:write).with(4, 2, /Found/)
      browse_screen.render_status(:done, 'Found 10 books')
    end

    it 'renders nothing for idle status' do
      expect(EbookReader::Terminal).not_to receive(:write).with(4, 2, anything)
      browse_screen.render_status(:idle, '')
    end
  end

  describe '#render_empty_state' do
    it 'shows scanning message when scanning' do
      expect(EbookReader::Terminal).to receive(:write).with(anything, anything,
                                                            /Scanning for books/)
      browse_screen.render_empty_state(24, 80, :scanning, false)
    end

    it 'shows no files message when no epubs found' do
      expect(EbookReader::Terminal).to receive(:write).with(anything, anything,
                                                            /No EPUB files found/)
      browse_screen.render_empty_state(24, 80, :done, true)
    end

    it 'shows no matches message when filtering' do
      expect(EbookReader::Terminal).to receive(:write).with(anything, anything, /No matching books/)
      browse_screen.render_empty_state(24, 80, :done, false)
    end
  end
end
