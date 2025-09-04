# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::AnnotationRepository do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:logger) { double('Logger', error: nil, debug: nil, info: nil) }

  class CtnAnnRepo
    def initialize(logger) = (@logger = logger)
    def resolve(name)
      return @logger if name == :logger
      nil
    end
  end

  before do
    stub_const('EbookReader::Annotations::AnnotationStore', Class.new do
      @data = Hash.new { |h, k| h[k] = [] }
      class << self; attr_reader :data; end
      def self.get(path) = @data[path]
      def self.all = @data
      def self.add(path, text, note, range, chapter_index, _meta)
        (@data[path] ||= []) << {
          'id' => SecureRandom.hex(4), 'text' => text, 'note' => note,
          'range' => range, 'chapter_index' => chapter_index, 'created_at' => Time.now.iso8601
        }
      end
      def self.update(path, id, note)
        ann = (@data[path] ||= []).find { |a| a['id'] == id }
        ann['note'] = note if ann
      end
      def self.delete(path, id)
        (@data[path] ||= []).reject! { |a| a['id'] == id }
      end
    end)
  end

  subject(:repo) { described_class.new(CtnAnnRepo.new(logger)) }
  let(:book_path) { '/tmp/book.epub' }

  it 'adds, lists, updates and deletes annotations' do
    a1 = repo.add_for_book(book_path, text: 't', note: 'n', range: { start: 1, end: 2 }, chapter_index: 0)
    expect(a1).to be_a(Hash)
    expect(repo.find_by_book_path(book_path)).not_to be_empty
    expect(repo.count_for_book(book_path)).to be >= 1
    expect(repo.find_by_chapter(book_path, 0)).not_to be_empty
    expect(repo.exists_in_range?(book_path, 0, { start: 1, end: 2 })).to be true

    id = a1['id']
    expect(repo.update_note(book_path, id, 'new')).to be true
    expect(repo.delete_by_id(book_path, id)).to be true
  end

  it 'validates parameters' do
    expect { repo.find_by_book_path(nil) }.to raise_error(described_class::ValidationError)
    expect { repo.add_for_book(nil, text: 't', note: 'n', range: { start: 0, end: 1 }, chapter_index: 0) }.to raise_error(described_class::ValidationError)
    expect { repo.update_note(nil, 'id', 'x') }.to raise_error(described_class::ValidationError)
    expect { repo.delete_by_id(nil, 'id') }.to raise_error(described_class::ValidationError)
  end
end

