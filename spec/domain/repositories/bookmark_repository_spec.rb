# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::BookmarkRepository do
  let(:mock_dependencies) do
    instance_double(EbookReader::Domain::DependencyContainer).tap do |deps|
      allow(deps).to receive(:resolve).with(:logger).and_return(mock_logger)
    end
  end

  let(:mock_logger) do
    class_double(EbookReader::Infrastructure::Logger).tap do |logger|
      allow(logger).to receive(:error)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:fatal)
    end
  end

  let(:mock_storage) { class_double(EbookReader::BookmarkManager) }
  
  let(:book_path) { '/path/to/test.epub' }
  let(:bookmark_data) do
    instance_double(EbookReader::Models::BookmarkData,
                    path: book_path,
                    chapter: 2,
                    line_offset: 100,
                    text: 'Test bookmark text')
  end
  let(:bookmark) do
    instance_double(EbookReader::Models::Bookmark,
                    chapter_index: 2,
                    line_offset: 100,
                    text_snippet: 'Test bookmark text',
                    created_at: Time.new(2023, 1, 1))
  end

  subject { described_class.new(mock_dependencies) }

  before do
    stub_const('EbookReader::BookmarkManager', mock_storage)
  end

  describe '#add_for_book' do
    let(:expected_bookmark_data) { instance_double(EbookReader::Models::BookmarkData) }

    before do
      allow(EbookReader::Models::BookmarkData).to receive(:new).and_return(expected_bookmark_data)
      allow(mock_storage).to receive(:add)
      allow(subject).to receive(:find_by_book_path).with(book_path).and_return([bookmark])
    end

    it 'creates BookmarkData with correct parameters' do
      expect(EbookReader::Models::BookmarkData).to receive(:new).with(
        path: book_path,
        chapter: 2,
        line_offset: 100,
        text: 'Test text'
      )

      subject.add_for_book(book_path, chapter_index: 2, line_offset: 100, text_snippet: 'Test text')
    end

    it 'calls storage add method' do
      expect(mock_storage).to receive(:add).with(expected_bookmark_data)

      subject.add_for_book(book_path, chapter_index: 2, line_offset: 100, text_snippet: 'Test text')
    end

    it 'returns the most recently created bookmark' do
      result = subject.add_for_book(book_path, chapter_index: 2, line_offset: 100, text_snippet: 'Test text')

      expect(result).to eq(bookmark)
    end

    it 'validates required parameters' do
      expect {
        subject.add_for_book(nil, chapter_index: 2, line_offset: 100, text_snippet: 'Test text')
      }.to raise_error(described_class::ValidationError, /Missing required parameters/)
    end

    it 'handles storage errors' do
      allow(mock_storage).to receive(:add).and_raise(StandardError, 'Storage error')

      expect {
        subject.add_for_book(book_path, chapter_index: 2, line_offset: 100, text_snippet: 'Test text')
      }.to raise_error(described_class::PersistenceError)
    end
  end

  describe '#find_by_book_path' do
    let(:bookmarks) { [bookmark] }

    before do
      allow(mock_storage).to receive(:get).with(book_path).and_return(bookmarks)
    end

    it 'calls storage get method with book path' do
      expect(mock_storage).to receive(:get).with(book_path)

      subject.find_by_book_path(book_path)
    end

    it 'returns bookmarks from storage' do
      result = subject.find_by_book_path(book_path)

      expect(result).to eq(bookmarks)
    end

    it 'returns empty array when storage returns nil' do
      allow(mock_storage).to receive(:get).with(book_path).and_return(nil)

      result = subject.find_by_book_path(book_path)

      expect(result).to eq([])
    end

    it 'validates required parameters' do
      expect {
        subject.find_by_book_path(nil)
      }.to raise_error(described_class::ValidationError, /Missing required parameters/)
    end

    it 'handles storage errors' do
      allow(mock_storage).to receive(:get).and_raise(StandardError, 'Storage error')

      expect {
        subject.find_by_book_path(book_path)
      }.to raise_error(described_class::PersistenceError)
    end
  end

  describe '#delete_for_book' do
    before do
      allow(mock_storage).to receive(:delete)
    end

    it 'calls storage delete method' do
      expect(mock_storage).to receive(:delete).with(book_path, bookmark)

      subject.delete_for_book(book_path, bookmark)
    end

    it 'returns true on successful deletion' do
      result = subject.delete_for_book(book_path, bookmark)

      expect(result).to be true
    end

    it 'validates required parameters' do
      expect {
        subject.delete_for_book(nil, bookmark)
      }.to raise_error(described_class::ValidationError, /Missing required parameters/)

      expect {
        subject.delete_for_book(book_path, nil)
      }.to raise_error(described_class::ValidationError, /Missing required parameters/)
    end

    it 'ensures bookmark entity exists' do
      expect {
        subject.delete_for_book(book_path, nil)
      }.to raise_error(described_class::EntityNotFoundError, 'Bookmark not found')
    end

    it 'handles storage errors' do
      allow(mock_storage).to receive(:delete).and_raise(StandardError, 'Storage error')

      expect {
        subject.delete_for_book(book_path, bookmark)
      }.to raise_error(described_class::PersistenceError)
    end
  end

  describe '#exists_at_position?' do
    let(:bookmarks) { [bookmark] }

    before do
      allow(bookmark).to receive(:chapter_index).and_return(2)
      allow(bookmark).to receive(:line_offset).and_return(100)
      allow(subject).to receive(:find_by_book_path).with(book_path).and_return(bookmarks)
    end

    it 'returns true when bookmark exists at position' do
      result = subject.exists_at_position?(book_path, 2, 100)

      expect(result).to be true
    end

    it 'returns false when no bookmark exists at position' do
      result = subject.exists_at_position?(book_path, 2, 200)

      expect(result).to be false
    end

    it 'handles storage errors' do
      allow(subject).to receive(:find_by_book_path).and_raise(StandardError, 'Storage error')

      expect {
        subject.exists_at_position?(book_path, 2, 100)
      }.to raise_error(described_class::PersistenceError)
    end
  end

  describe '#count_for_book' do
    let(:bookmarks) { [bookmark, bookmark] }

    before do
      allow(subject).to receive(:find_by_book_path).with(book_path).and_return(bookmarks)
    end

    it 'returns the count of bookmarks' do
      result = subject.count_for_book(book_path)

      expect(result).to eq(2)
    end

    it 'handles storage errors' do
      allow(subject).to receive(:find_by_book_path).and_raise(StandardError, 'Storage error')

      expect {
        subject.count_for_book(book_path)
      }.to raise_error(described_class::PersistenceError)
    end
  end

  describe '#find_at_position' do
    let(:bookmarks) { [bookmark] }

    before do
      allow(bookmark).to receive(:chapter_index).and_return(2)
      allow(bookmark).to receive(:line_offset).and_return(100)
      allow(subject).to receive(:find_by_book_path).with(book_path).and_return(bookmarks)
    end

    it 'returns bookmark when found at position' do
      result = subject.find_at_position(book_path, 2, 100)

      expect(result).to eq(bookmark)
    end

    it 'returns nil when no bookmark found at position' do
      result = subject.find_at_position(book_path, 2, 200)

      expect(result).to be_nil
    end

    it 'handles storage errors' do
      allow(subject).to receive(:find_by_book_path).and_raise(StandardError, 'Storage error')

      expect {
        subject.find_at_position(book_path, 2, 100)
      }.to raise_error(described_class::PersistenceError)
    end
  end
end