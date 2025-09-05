# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AnnotationRepository + FileStore integration' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:config_dir) { File.join(home, '.config', 'reader') }
  let(:deps) do
    # Only logger is resolved
    Class.new do
      def resolve(name)
        return EbookReader::Infrastructure::Logger if name == :logger
        nil
      end
    end.new
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

