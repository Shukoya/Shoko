# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe EbookReader::Infrastructure::BookCachePipeline do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:epub_path) { File.join(tmp_dir, 'spec_book.epub') }
  let(:image_payload) { "\xFF" * (128 * 1024) }
  let(:zip_entries) do
    [
      { name: 'mimetype', data: 'application/epub+zip', method: :store },
      {
        name: 'META-INF/container.xml',
        data: <<~XML,
          <?xml version="1.0" encoding="UTF-8"?>
          <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
              <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
          </container>
        XML
      },
      {
        name: 'OPS/content.opf',
        data: <<~XML,
          <?xml version="1.0" encoding="UTF-8"?>
          <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title>Spec Book</dc:title>
              <dc:language>en</dc:language>
              <dc:creator>Author One</dc:creator>
              <dc:creator>Author Two</dc:creator>
              <dc:date>2020-01-01</dc:date>
            </metadata>
            <manifest>
              <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
              <item id="chap1" href="xhtml/chapter1.xhtml" media-type="application/xhtml+xml"/>
              <item id="image1" href="images/pic.jpg" media-type="image/jpeg"/>
            </manifest>
            <spine toc="ncx">
              <itemref idref="chap1"/>
            </spine>
          </package>
        XML
      },
      {
        name: 'OPS/toc.ncx',
        data: <<~XML,
          <?xml version="1.0" encoding="UTF-8"?>
          <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <head>
              <meta name="dtb:uid" content="BookId"/>
            </head>
            <docTitle><text>Spec Book</text></docTitle>
            <navMap>
              <navPoint id="navPoint-1" playOrder="1">
                <navLabel><text>Chapter 1</text></navLabel>
                <content src="xhtml/chapter1.xhtml"/>
              </navPoint>
            </navMap>
          </ncx>
        XML
      },
      {
        name: 'OPS/xhtml/chapter1.xhtml',
        data: <<~HTML,
          <?xml version="1.0" encoding="UTF-8"?>
          <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title>Chapter 1</title></head>
            <body><p>Hello <img src="../images/pic.jpg" alt="pic"/></p></body>
          </html>
        HTML
      },
      { name: 'OPS/images/pic.jpg', data: image_payload, method: :store },
    ]
  end
  let(:pipeline) { described_class.new(cache_root: File.join(tmp_dir, '.cache', 'reader')) }

  before do
    @old_home = Dir.home
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['HOME'] = tmp_dir
    ENV['XDG_CACHE_HOME'] = File.join(tmp_dir, '.cache')
    File.binwrite(epub_path, ZipTestBuilder.build_zip(zip_entries))
  end

  after do
    ENV['HOME'] = @old_home
    ENV['XDG_CACHE_HOME'] = @old_cache
    FileUtils.rm_rf(tmp_dir)
  end

  it 'imports an EPUB and writes a SQLite-backed cache' do
    result = pipeline.load(epub_path)
    expect(result.loaded_from_cache).to be(false)
    expect(File.exist?(result.cache_path)).to be(true)
    db_path = File.join(File.dirname(result.cache_path), EbookReader::Infrastructure::CacheDatabase::DB_FILENAME)
    expect(File.exist?(db_path)).to be(true)
    expect(result.book.title).to eq('Spec Book')
    expect(result.book.resources['OPS/images/pic.jpg'].bytesize).to eq(image_payload.bytesize)
  end

  it 'returns cached data on subsequent loads' do
    pipeline.load(epub_path)
    cache = EbookReader::Infrastructure::EpubCache.new(epub_path, cache_root: File.join(tmp_dir, '.cache', 'reader'))
    expect(cache.load_for_source(strict: false)).not_to be_nil
    warmed = pipeline.load(epub_path)
    expect(warmed.loaded_from_cache).to be(true)
    expect(warmed.book.chapters.first.title).to eq('Chapter 1')
  end

  it 'repairs the pointer file when it is corrupted' do
    first = pipeline.load(epub_path)
    File.write(first.cache_path, 'corrupt-data')

    second = pipeline.load(epub_path)
    expect(second.loaded_from_cache).to be(true)
    expect(File.exist?(second.cache_path)).to be(true)

    pointer = JSON.parse(File.read(second.cache_path))
    expect(pointer['format']).to eq(EbookReader::Infrastructure::CachePointerManager::POINTER_FORMAT)
  end

  it 'raises a CacheLoadError when opening an invalid cache file directly' do
    result = pipeline.load(epub_path)
    File.write(result.cache_path, 'broken')

    expect do
      pipeline.load(result.cache_path)
    end.to raise_error(EbookReader::CacheLoadError)
  end

  it 'handles EPUBs that omit table-of-contents data' do
    alt_path = File.join(tmp_dir, 'no_toc.epub')
    entries = [
      { name: 'META-INF/container.xml', data: <<~XML },
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
      XML
      {
        name: 'OPS/content.opf',
        data: <<~XML,
          <?xml version="1.0" encoding="UTF-8"?>
          <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title>No TOC</dc:title>
              <dc:language>en</dc:language>
            </metadata>
            <manifest>
              <item id="chap1" href="xhtml/chapter1.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
              <itemref idref="chap1"/>
            </spine>
          </package>
        XML
      },
      {
        name: 'OPS/xhtml/chapter1.xhtml',
        data: <<~HTML,
          <?xml version="1.0" encoding="UTF-8"?>
          <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title></title></head>
            <body><p>Content</p></body>
          </html>
        HTML
      },
    ]
    File.binwrite(alt_path, ZipTestBuilder.build_zip(entries))

    result = pipeline.load(alt_path)
    expect(result.book.toc_entries).to eq([])
    expect(result.book.chapters.first.title).to eq('Chapter 1')
  end
end
