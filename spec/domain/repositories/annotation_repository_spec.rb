# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::AnnotationRepository do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:logger) { double('Logger', error: nil, debug: nil, info: nil) }

  class CtnAnnRepo
    def initialize(logger, file_writer, path_service)
      @logger = logger
      @file_writer = file_writer
      @path_service = path_service
    end

    def resolve(name)
      case name
      when :logger then @logger
      when :file_writer then @file_writer
      when :path_service then @path_service
      end
    end
  end

  let(:file_writer) { instance_double('FileWriter', write: true) }
  let(:path_service) { instance_double('PathService', reader_config_path: '/tmp/annotations.json') }

  let(:store) do
    Class.new do
      def initialize
        @data = Hash.new { |h, k| h[k] = [] }
      end

      def get(path) = @data[path]
      def all = @data

      def add(path, text, note, range, chapter_index, _meta)
        (@data[path] ||= []) << {
          'id' => 'id1', 'text' => text, 'note' => note,
          'range' => range, 'chapter_index' => chapter_index, 'created_at' => Time.now.iso8601
        }
      end

      def update(path, id, note)
        ann = (@data[path] ||= []).find { |a| a['id'] == id }
        ann['note'] = note if ann
      end

      def delete(path, id)
        (@data[path] ||= []).reject! { |a| a['id'] == id }
      end
    end.new
  end

  before do
    allow(EbookReader::Domain::Repositories::Storage::AnnotationFileStore).to receive(:new)
      .with(file_writer:, path_service:)
      .and_return(store)
  end

  subject(:repo) { described_class.new(CtnAnnRepo.new(logger, file_writer, path_service)) }
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
