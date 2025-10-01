# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::AtomicFileWriter do
  include FakeFS::SpecHelpers

  let(:path) { '/tmp/output/test.txt' }

  it 'writes data atomically via helper' do
    described_class.write(path, 'payload')
    expect(File.read(path)).to eq('payload')
  end

  it 'supports custom IO writes' do
    described_class.write_using(path, binary: false) do |io|
      io.write('line1')
      io.write('line2')
    end
    expect(File.read(path)).to eq('line1line2')
  end
end
