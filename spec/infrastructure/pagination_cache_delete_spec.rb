# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pagination cache delete' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:cache_root) { File.join(home, '.cache') }
  let(:reader_root) { File.join(cache_root, 'reader') }
  let(:book_dir) { File.join(reader_root, 'cafebabe') }
  let(:doc) { Struct.new(:cache_dir).new(book_dir) }
  let(:key) { EbookReader::Infrastructure::PaginationCache.layout_key(80, 24, :single, :normal) }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = cache_root
    FileUtils.mkdir_p(File.join(book_dir, 'pagination'))
    File.write(File.join(book_dir, 'pagination', "#{key}.json"), '[]')
  end

  it 'removes existing cache files for a layout' do
    expect(EbookReader::Infrastructure::PaginationCache.exists_for_document?(doc, key)).to be true
    ok = EbookReader::Infrastructure::PaginationCache.delete_for_document(doc, key)
    expect(ok).to be true
    expect(EbookReader::Infrastructure::PaginationCache.exists_for_document?(doc, key)).to be false
  end
end

