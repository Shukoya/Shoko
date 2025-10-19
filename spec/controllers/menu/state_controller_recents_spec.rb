# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe EbookReader::Controllers::Menu::StateController do
  subject(:controller) { described_class.new(menu) }

  let(:state) do
    EbookReader::Infrastructure::ObserverStateStore.new(
      EbookReader::Infrastructure::EventBus.new
    )
  end
  let(:catalog) { instance_double('Catalog') }
  let(:terminal_service) { instance_double('Terminal') }
  let(:recent_repository) { instance_double(EbookReader::Domain::Repositories::RecentLibraryRepository) }
  let(:dependencies) do
    double('Dependencies').tap do |dep|
      allow(dep).to receive(:resolve) do |name|
        case name
        when :recent_library_repository then recent_repository
        when :cache_service then cache_service
        else
          raise "Unexpected dependency resolve: #{name}"
        end
      end
      allow(dep).to receive(:registered?).and_return(false)
    end
  end
  let(:cache_service) do
    double('CacheService').tap do |svc|
      allow(svc).to receive(:valid_cache?).and_return(true)
      allow(svc).to receive(:cache_file?).and_return(true)
      allow(svc).to receive(:canonical_source_path) do |path|
        path == cache_path ? epub_path : path
      end
    end
  end
  let(:menu) do
    instance_double(
      'Menu',
      dependencies: dependencies,
      state: state,
      catalog: catalog,
      terminal_service: terminal_service,
      switch_to_mode: nil
    )
  end

  let(:tmp_home) { Dir.mktmpdir }
  let(:cache_root) { File.join(tmp_home, '.cache') }
  let(:books_dir) { File.join(tmp_home, 'books') }
  let(:epub_path) { File.join(books_dir, 'cached.epub') }
  let(:cache_path) do
    EbookReader::Infrastructure::EpubCache.new(epub_path).cache_path
  end

  before do
    @home_was = ENV['HOME']
    @xdg_cache_was = ENV['XDG_CACHE_HOME']
    ENV['HOME'] = tmp_home
    ENV['XDG_CACHE_HOME'] = cache_root

    FileUtils.mkdir_p(books_dir)
    build_sample_epub(epub_path)
    EbookReader::EPUBDocument.new(epub_path) # populate cache

    allow(EbookReader::Application::PaginationOrchestrator).to receive(:new).and_return(double)
    allow(EbookReader::MainMenu::MenuProgressPresenter).to receive(:new).and_return(double(show: nil, clear: nil, update: nil))
    allow(EbookReader::MouseableReader).to receive(:new).and_return(instance_double('MouseableReader', run: nil))

    allow(controller).to receive(:ensure_reader_document_for).and_return(true)
    allow(state).to receive(:dispatch)
  end

  after do
    ENV['HOME'] = @home_was
    ENV['XDG_CACHE_HOME'] = @xdg_cache_was
    FileUtils.remove_entry(tmp_home)
  end

  describe '#run_reader' do
    it 'records the canonical EPUB path when opening from the cache file' do
      expect(recent_repository).to receive(:add).with(epub_path)

      controller.run_reader(cache_path)
    end
  end

  def build_sample_epub(path)
    data = ZipTestBuilder.build_zip([
                                      {
                                        name: 'META-INF/container.xml',
                                        data: <<~XML,
                                          <?xml version="1.0" encoding="UTF-8"?>
                                          <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                                            <rootfiles>
                                              <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                                            </rootfiles>
                                          </container>
                                        XML
                                        method: :deflate,
                                      },
                                      {
                                        name: 'OEBPS/content.opf',
                                        data: <<~OPF,
                                          <?xml version="1.0" encoding="UTF-8"?>
                                          <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
                                            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                                              <dc:title>Cached Book</dc:title>
                                            </metadata>
                                            <manifest>
                                              <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
                                            </manifest>
                                            <spine>
                                              <itemref idref="ch1"/>
                                            </spine>
                                          </package>
                                        OPF
                                        method: :deflate,
                                      },
                                      {
                                        name: 'OEBPS/ch1.xhtml',
                                        data: '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Hi</p></body></html>',
                                        method: :deflate,
                                      },
                                    ])
    File.binwrite(path, data)
  end
end
