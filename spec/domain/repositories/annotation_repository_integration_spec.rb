# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AnnotationRepository + FileStore integration' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:config_dir) { File.join(home, '.config', 'reader') }
  let(:file_writer) do
    instance_double('FileWriter').tap do |writer|
      allow(writer).to receive(:write) do |path, payload|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, payload)
      end
    end
  end

  let(:path_service) do
    instance_double('PathService').tap do |service|
      allow(service).to receive(:reader_config_path) do |*segments|
        File.join(config_dir, *segments)
      end
    end
  end

  let(:deps) do
    Class.new do
      def initialize(file_writer, path_service)
        @file_writer = file_writer
        @path_service = path_service
      end

      def resolve(name)
        case name
        when :logger then EbookReader::Infrastructure::Logger
        when :file_writer then @file_writer
        when :path_service then @path_service
        end
      end
    end.new(file_writer, path_service)
  end

  before do
    ENV['HOME'] = home
    FileUtils.mkdir_p(config_dir)
  end

  it 'round-trips add/list/update/delete through file store' do
    repo = EbookReader::Domain::Repositories::AnnotationRepository.new(deps)
    path = '/tmp/book.epub'
    a1 = repo.add_for_book(path, text: 't', note: 'n', range: { start: 0, end: 10 }, chapter_index: 0)
    expect(a1).to be_a(Hash)
    list = repo.find_by_book_path(path)
    expect(list.length).to eq(1)
    id = list.first['id']
    expect(repo.update_note(path, id, 'changed')).to be true
    expect(repo.find_by_book_path(path).first['note']).to eq('changed')
    expect(repo.delete_by_id(path, id)).to be true
    expect(repo.find_by_book_path(path)).to be_empty
  end
end
