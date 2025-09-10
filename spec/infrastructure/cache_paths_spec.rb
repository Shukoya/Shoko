# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::CachePaths do
  include FakeFS::SpecHelpers

  it 'uses XDG_CACHE_HOME when set' do
    ENV['XDG_CACHE_HOME'] = '/tmp/xdg'
    expect(described_class.reader_root).to eq('/tmp/xdg/reader')
  end

  it 'falls back to ~/.cache when XDG is not set' do
    ENV.delete('XDG_CACHE_HOME')
    ENV['HOME'] = '/home/test'
    expect(described_class.reader_root).to eq('/home/test/.cache/reader')
  end
end
