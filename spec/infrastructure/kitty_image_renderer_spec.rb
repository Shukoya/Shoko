# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe EbookReader::Infrastructure::KittyImageRenderer do
  def minimal_png(width:, height:)
    signature = "\x89PNG\r\n\x1a\n".b
    ihdr_len = [13].pack('N')
    ihdr_type = 'IHDR'.b
    ihdr_data = [width, height].pack('N2') + "\x08\x06\x00\x00\x00".b
    fake_crc = "\x00\x00\x00\x00".b
    signature + ihdr_len + ihdr_type + ihdr_data + fake_crc
  end

  it 'recreates virtual placements on every prepare_virtual call' do
    allow(EbookReader::Infrastructure::KittyGraphics).to receive(:supported?).and_return(true)

    epub = Tempfile.new(['demo', '.epub'])
    epub.close

    resource_loader = instance_double(EbookReader::Infrastructure::EpubResourceLoader)
    transcoder = instance_double(EbookReader::Infrastructure::ImageTranscoder)

    allow(resource_loader).to receive(:fetch).and_return('RAW'.b)
    allow(transcoder).to receive(:to_png).and_return(minimal_png(width: 100, height: 50))
    allow(resource_loader).to receive(:store).and_return(true)

    expect(EbookReader::Infrastructure::KittyGraphics).to receive(:transmit_png).once.and_return(['TX'])
    expect(EbookReader::Infrastructure::KittyGraphics).to receive(:virtual_place).twice do |image_id, **kwargs|
      expect(image_id).to be_a(Integer)
      expect(kwargs[:cols]).to eq(10)
      expect(kwargs[:rows]).to eq(5)
      expect(kwargs[:placement_id]).to eq(123)
      'VP'
    end

    renderer = described_class.new(resource_loader: resource_loader, transcoder: transcoder)

    output = EbookReader::TestSupport::TerminalDouble
    output.reset!

    2.times do
      renderer.prepare_virtual(
        output: output,
        book_sha: 'a' * 64,
        epub_path: epub.path,
        chapter_entry_path: 'OEBPS/ch1.xhtml',
        src: 'img1.jpg',
        cols: 10,
        rows: 5,
        placement_id: 123,
        z: -1
      )
    end

    texts = output.printed
    expect(texts.grep('TX').length).to eq(1)
    expect(texts.grep('VP').length).to eq(2)
  ensure
    epub&.unlink
  end
end
