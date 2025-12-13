# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::KittyImageRenderer do
  def fake_png(width:, height:)
    signature = "\x89PNG\r\n\x1a\n".b
    ihdr_data = [width, height].pack('N2') + "\x08\x06\x00\x00\x00".b
    ihdr_chunk = [ihdr_data.bytesize].pack('N') + 'IHDR' + ihdr_data + "\x00\x00\x00\x00".b
    signature + ihdr_chunk
  end

  class FakeResourceLoader
    attr_reader :fetches, :stores

    def initialize(bytes_by_entry_path)
      @bytes_by_entry_path = bytes_by_entry_path
      @fetches = []
      @stores = []
    end

    def fetch(book_sha:, epub_path:, entry_path:, persist: false, cache_key: nil)
      @fetches << { book_sha: book_sha, epub_path: epub_path, entry_path: entry_path, persist: persist, cache_key: cache_key }
      @bytes_by_entry_path.fetch(entry_path)
    end

    def store(book_sha:, entry_path:, bytes:)
      @stores << { book_sha: book_sha, entry_path: entry_path, bytes: bytes }
      true
    end
  end

  around do |example|
    Dir.mktmpdir('reader-kitty-renderer') do |dir|
      @tmp_dir = dir
      @epub_path = File.join(dir, 'book.epub')
      File.write(@epub_path, 'not a real epub')
      example.run
    end
  end

  before do
    allow(EbookReader::Infrastructure::KittyGraphics).to receive(:transmit_png).and_return([])
    EbookReader::TestSupport::TerminalDouble.reset!
  end

  it 'uses distinct image ids per entry path' do
    bytes = fake_png(width: 10, height: 10)
    loader = FakeResourceLoader.new(
      'OEBPS/img1.png' => bytes,
      'OEBPS/img2.png' => bytes
    )
    renderer = described_class.new(resource_loader: loader)

    renderer.render(
      output: EbookReader::TestSupport::TerminalDouble,
      book_sha: 'a' * 64,
      epub_path: @epub_path,
      chapter_entry_path: 'OEBPS/ch1.xhtml',
      src: 'img1.png',
      row: 5,
      col: 5,
      cols: 40,
      rows: 10,
      placement_id: 11
    )

    renderer.render(
      output: EbookReader::TestSupport::TerminalDouble,
      book_sha: 'a' * 64,
      epub_path: @epub_path,
      chapter_entry_path: 'OEBPS/ch1.xhtml',
      src: 'img2.png',
      row: 5,
      col: 5,
      cols: 40,
      rows: 10,
      placement_id: 12
    )

    expect(loader.fetches.length).to eq(2)
    place_writes = EbookReader::TestSupport::TerminalDouble.writes.map { |w| w[:text] }
    ids = place_writes.filter_map { |text| text[/\bi=(\d+)\b/, 1] }.map(&:to_i)
    expect(ids.length).to eq(2)
    expect(ids.uniq.length).to eq(2)
  end

  it 'fits portrait images without distortion by centering horizontally' do
    bytes = fake_png(width: 100, height: 200)
    loader = FakeResourceLoader.new('OEBPS/portrait.png' => bytes)
    renderer = described_class.new(resource_loader: loader)

    renderer.render(
      output: EbookReader::TestSupport::TerminalDouble,
      book_sha: 'a' * 64,
      epub_path: @epub_path,
      chapter_entry_path: 'OEBPS/ch1.xhtml',
      src: 'portrait.png',
      row: 10,
      col: 5,
      cols: 80,
      rows: 18,
      placement_id: 7
    )

    writes = EbookReader::TestSupport::TerminalDouble.writes
    expect(writes.length).to eq(1)
    expect(writes.first[:row]).to eq(10)
    expect(writes.first[:col]).to eq(36) # centered within 80 columns: offset 31
    expect(writes.first[:text]).to match(/\bc=18\b/)
    expect(writes.first[:text]).to match(/\br=18\b/)
  end

  it 'fits wide images without distortion by reducing rows' do
    bytes = fake_png(width: 400, height: 100)
    loader = FakeResourceLoader.new('OEBPS/wide.png' => bytes)
    renderer = described_class.new(resource_loader: loader)

    renderer.render(
      output: EbookReader::TestSupport::TerminalDouble,
      book_sha: 'a' * 64,
      epub_path: @epub_path,
      chapter_entry_path: 'OEBPS/ch1.xhtml',
      src: 'wide.png',
      row: 10,
      col: 5,
      cols: 80,
      rows: 18,
      placement_id: 8
    )

    writes = EbookReader::TestSupport::TerminalDouble.writes
    expect(writes.length).to eq(1)
    expect(writes.first[:row]).to eq(10)
    expect(writes.first[:col]).to eq(5)
    expect(writes.first[:text]).to match(/\bc=80\b/)
    expect(writes.first[:text]).to match(/\br=10\b/)
  end
end
