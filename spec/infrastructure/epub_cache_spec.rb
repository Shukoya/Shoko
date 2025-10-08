# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe EbookReader::Infrastructure::EpubCache do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_dir, 'cache') }

  before do
    allow(EbookReader::Infrastructure::CachePaths).to receive(:reader_root).and_return(cache_root)
  end

  after do
    FileUtils.remove_entry(tmp_dir) if File.exist?(tmp_dir)
  end

  it 'skips copying entries that escape the cache directory' do
    Dir.mktmpdir do |dir|
      epub_path = File.join(dir, 'book.epub')
      File.write(epub_path, 'fake-epub')

      cache = described_class.new(epub_path)
      zip = instance_double('Zip::File')

      allow(zip).to receive(:read).with('META-INF/container.xml').and_return('<xml/>')
      allow(zip).to receive(:read).with('OEBPS/content.opf').and_return('<opf/>')
      allow(zip).to receive(:read).with('OEBPS/../evil.lua').and_return('puts :evil')

      cache.populate!(zip, 'OEBPS/content.opf', ['OEBPS/../evil.lua'])

      expect(File.exist?(File.join(cache.cache_dir, 'META-INF', 'container.xml'))).to be(true)
      expect(File.exist?(File.join(cache.cache_dir, 'OEBPS', 'content.opf'))).to be(true)
      expect(File.exist?(File.join(cache.cache_dir, 'evil.lua'))).to be(true)
      expect(File.exist?(File.expand_path('../evil.lua', cache.cache_dir))).to be(false)
    end
  end
end
