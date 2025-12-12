# frozen_string_literal: true

require 'spec_helper'
require 'zip'

RSpec.describe Zip::File do
  include ZipTestBuilder

  it 'reads stored and deflated entries by name', :fakefs do
    data = ZipTestBuilder.build_zip([
                                      { name: 'a.txt', data: 'hello', method: :store },
                                      { name: 'b/b.txt', data: 'world!', method: :deflate },
                                    ], comment: 'tiny comment to exercise EOCD scan')

    path = '/test.zip'
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, data)

    Zip::File.open(path) do |zip|
      expect(zip.find_entry('a.txt')).not_to be_nil
      expect(zip.find_entry('b/b.txt')).not_to be_nil
      expect(zip.read('a.txt')).to eq('hello'.b)
      expect(zip.read('b/b.txt')).to eq('world!'.b)
      expect { zip.read('missing.txt') }.to raise_error(Zip::Error)
    end
  end

  it 'raises on unsupported compression method', :fakefs do
    # method 99 is arbitrary unsupported
    data = ZipTestBuilder.build_zip([
                                      { name: 'x.bin', data: 'data', method: 99 },
                                    ])

    path = '/unsupported.zip'
    File.binwrite(path, data)

    Zip::File.open(path) do |zip|
      expect(zip.find_entry('x.bin')).not_to be_nil
      expect { zip.read('x.bin') }.to raise_error(Zip::Error, /unsupported compression/i)
    end
  end

  it 'enforces per-entry size limits', :fakefs do
    previous = ENV['READER_ZIP_MAX_ENTRY_BYTES']
    ENV['READER_ZIP_MAX_ENTRY_BYTES'] = '5'

    data = ZipTestBuilder.build_zip([
                                      { name: 'big.txt', data: 'hello world', method: :deflate },
                                    ])

    path = '/too_big.zip'
    File.binwrite(path, data)

    Zip::File.open(path) do |zip|
      expect { zip.read('big.txt') }.to raise_error(Zip::Error, /entry too large/i)
    end
  ensure
    ENV['READER_ZIP_MAX_ENTRY_BYTES'] = previous
  end

  it 'enforces total uncompressed size limits across reads', :fakefs do
    previous = ENV['READER_ZIP_MAX_TOTAL_BYTES']
    ENV['READER_ZIP_MAX_TOTAL_BYTES'] = '5'

    data = ZipTestBuilder.build_zip([
                                      { name: 'a.txt', data: '1234', method: :store },
                                      { name: 'b.txt', data: '5678', method: :store },
                                    ])

    path = '/too_total.zip'
    File.binwrite(path, data)

    Zip::File.open(path) do |zip|
      expect(zip.read('a.txt')).to eq('1234'.b)
      expect { zip.read('b.txt') }.to raise_error(Zip::Error, /total uncompressed/i)
    end
  ensure
    ENV['READER_ZIP_MAX_TOTAL_BYTES'] = previous
  end
end
