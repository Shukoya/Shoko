# frozen_string_literal: true

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
end
