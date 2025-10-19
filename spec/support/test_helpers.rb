# frozen_string_literal: true

module TestHelpers
  def create_test_epub(path = '/test.epub')
    FakeFS do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'fake epub content')
    end
    path
  end

  def mock_terminal(width: 80, height: 24)
    terminal = EbookReader::Terminal
    if terminal.respond_to?(:size=)
      terminal.size = [height, width]
    elsif terminal.respond_to?(:configure_size)
      terminal.configure_size(height: height, width: width)
    end
  end

  def test_terminal_service(container = nil)
    svc = if container
            container.resolve(:terminal_service)
          else
            EbookReader::Domain::ContainerFactory.create_default_container.resolve(:terminal_service)
          end
    raise 'Test terminal service unavailable' unless svc.respond_to?(:queue_input)

    svc
  end

  def create_test_dependencies
    EbookReader::Domain::DependencyContainer.new.tap do |container|
      config_root = Dir.mktmpdir('reader-config')
      cache_root = Dir.mktmpdir('reader-cache')

      container.register(:state_store, EbookReader::Infrastructure::StateStore.new)
      container.register(:event_bus, EbookReader::Infrastructure::EventBus.new)
      container.register(:logger, RSpec::Mocks::Double.new('Logger', info: nil, error: nil, debug: nil))
      container.register(:atomic_file_writer, EbookReader::Infrastructure::AtomicFileWriter)
      container.register(:cache_paths, instance_double('CachePaths', reader_root: cache_root))
      container.register(:epub_cache_factory, lambda { |path| EbookReader::Infrastructure::EpubCache.new(path) })
      container.register(:epub_cache_predicate, lambda { |path| EbookReader::Infrastructure::EpubCache.cache_file?(path) })

      path_service = instance_double('PathService')
      allow(path_service).to receive(:reader_config_root).and_return(config_root)
      allow(path_service).to receive(:reader_config_path) do |*segments|
        File.join(config_root, *segments)
      end
      allow(path_service).to receive(:cache_root).and_return(cache_root)
      container.register(:path_service, path_service)

      container.register(:file_writer, EbookReader::Domain::Services::FileWriterService.new(container))
      container.register(:performance_monitor, nil)
      container.register(:perf_tracer, nil)
      container.register(:instrumentation_service, EbookReader::Domain::Services::InstrumentationService.new(container))
    end
  end

  def stub_document_service(chapters:, doc_attrs: {})
    attrs = { title: 'Doc', language: 'en', cached?: false }.merge(doc_attrs)
    chapter_payload = chapters
    doc_class = Class.new do
      attr_reader :chapters

      define_method(:initialize) do |chapters, attrs|
        @chapters = chapters
        @attrs = attrs
      end

      define_method(:chapter_count) { @chapters.length }
      define_method(:get_chapter) { |index| @chapters[index] }

      define_method(:method_missing) do |name, *args, &block|
        return super unless args.empty? && @attrs.key?(name)

        value = @attrs[name]
        value.respond_to?(:call) ? value.call(self) : value
      end

      define_method(:respond_to_missing?) do |name, include_private = false|
        @attrs.key?(name) || super(name, include_private)
      end
    end

    service_class = Class.new do
      define_method(:initialize) { |_path, *_args| }

      define_method(:load_document) do
        chapter_data = chapter_payload.map do |chapter|
          chapter.respond_to?(:dup) ? chapter.dup : chapter
        end
        doc_class.new(chapter_data, attrs)
      end
    end

    stub_const('EbookReader::Infrastructure::DocumentService', service_class)
    doc_class
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
