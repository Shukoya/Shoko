# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::LibraryService do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_root) { File.join(xdg_cache, 'reader') }
  let(:book_dir) { File.join(reader_root, 'deadbeef') }

  let(:dependencies) do
    # Minimal container double
    Class.new do
      def resolve(_name) = nil
    end.new
  end

  subject(:service) { described_class.new(dependencies) }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    FileUtils.mkdir_p(File.join(book_dir, 'META-INF'))
    FileUtils.mkdir_p(File.join(book_dir, 'OPS'))
    File.write(File.join(book_dir, 'META-INF', 'container.xml'), '<xml/>')
    File.write(File.join(book_dir, 'OPS', 'content.opf'), '<xml/>')
    # Simple manifest.json
    File.write(File.join(book_dir, 'manifest.json'), JSON.generate({
                                                                     'title' => 'Test Book',
                                                                     'author' => 'Tester',
                                                                     'authors' => ['Tester'],
                                                                     'opf_path' => 'OPS/content.opf',
                                                                     'spine' => ['OPS/ch1.xhtml'],
                                                                     'epub_path' => '/tmp/book.epub',
                                                                   }))
    File.write(File.join(book_dir, 'OPS', 'ch1.xhtml'), '<html><body><p>Hi</p></body></html>')
  end

  it 'lists cached books with basic metadata' do
    items = service.list_cached_books
    expect(items.length).to eq(1)
    book = items.first
    expect(book[:title]).to eq('Test Book')
    expect(book[:authors]).to eq('Tester')
    expect(book[:open_path]).to eq(book_dir)
    expect(book[:epub_path]).to eq('/tmp/book.epub')
    # year may be empty since OPF has no year; ensure key exists
    expect(book).to have_key(:year)
  end

  it 'loads msgpack manifest when available' do
    mp_path = File.join(book_dir, 'manifest.msgpack')
    File.write(mp_path, 'binary')
    serializer = instance_double(EbookReader::Infrastructure::MessagePackSerializer)
    allow(EbookReader::Infrastructure::MessagePackSerializer).to receive(:new).and_return(serializer)
    allow(serializer).to receive(:load_file).with(mp_path).and_return({
                                                                        'title' => 'MP', 'author' => 'A', 'authors' => ['A'], 'opf_path' => 'OPS/content.opf', 'spine' => ['OPS/ch1.xhtml'], 'epub_path' => '/x.epub'
                                                                      })

    items = service.list_cached_books
    expect(items.length).to eq(1)
    expect(items.first[:title]).to eq('MP')
  end
end
