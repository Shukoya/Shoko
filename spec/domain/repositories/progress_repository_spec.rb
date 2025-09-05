# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::ProgressRepository do
  let(:logger) { double('Logger', error: nil, debug: nil, info: nil) }
  class CtnProg
    def initialize(logger) = (@logger = logger)
    def resolve(name)
      return @logger if name == :logger
      nil
    end
  end

  let(:store) do
    Class.new do
      def initialize
        @store = {}
      end
      def save(path, ch, off)
        @store[path] = { 'chapter' => ch, 'line_offset' => off, 'timestamp' => Time.now.iso8601 }
        true
      end
      def load(path)
        @store[path]
      end
      def load_all
        @store
      end
    end.new
  end

  before do
    allow(EbookReader::Domain::Repositories::Storage::ProgressFileStore).to receive(:new).and_return(store)
  end

  subject(:repo) { described_class.new(CtnProg.new(logger)) }
  let(:book_path) { '/tmp/p.epub' }

  it 'saves, loads, checks existence and lists recent' do
    pd = repo.save_for_book(book_path, chapter_index: 1, line_offset: 10)
    expect(pd.chapter_index).to eq(1)
    expect(repo.exists_for_book?(book_path)).to be true
    expect(repo.find_by_book_path(book_path)).not_to be_nil
    expect(repo.recent_books).to include(book_path)
    expect(repo.last_updated_at(book_path)).to be_a(Time)
  end

  it 'save_if_further respects position ordering' do
    repo.save_for_book(book_path, chapter_index: 1, line_offset: 10)
    # Not further
    current = repo.save_if_further(book_path, chapter_index: 1, line_offset: 5)
    expect(current.line_offset).to eq(10)
    # Further
    current = repo.save_if_further(book_path, chapter_index: 2, line_offset: 0)
    expect(current.chapter_index).to eq(2)
  end

  it 'returns limited recent books and nil for missing last_updated_at' do
    # No progress for this path yet
    expect(repo.last_updated_at('/tmp/none.epub')).to be_nil
    # Add multiple
    repo.save_for_book('/tmp/a.epub', chapter_index: 0, line_offset: 0)
    repo.save_for_book('/tmp/b.epub', chapter_index: 0, line_offset: 0)
    expect(repo.recent_books(limit: 1).length).to eq(1)
  end
end
