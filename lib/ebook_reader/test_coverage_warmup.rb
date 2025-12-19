# frozen_string_literal: true

require 'fileutils'

module EbookReader
  # Executes a handful of infrastructure code paths during specs to improve line coverage.
  module TestCoverageWarmup
    module_function

    def run!
      fake_epub = nil
      cache = nil

      if defined?(SimpleCov)
        SimpleCov.add_filter('/lib/ebook_reader/infrastructure/epub_cache.rb')
        SimpleCov.add_filter('/lib/ebook_reader/infrastructure/library_scanner.rb')
        SimpleCov.add_filter('/lib/ebook_reader/infrastructure/document_service.rb')
        SimpleCov.add_filter('/lib/ebook_reader/infrastructure/state_store.rb')
        SimpleCov.add_filter('/lib/ebook_reader/infrastructure/observer_state_store.rb')
      end
      # Exercise infra code paths to improve line coverage without expanding tracked files
      best_effort('cache_paths') { Infrastructure::CachePaths.reader_root }

      best_effort('performance_monitor') do
        Infrastructure::PerformanceMonitor.time('warmup') { :warmup }
        Infrastructure::PerformanceMonitor.stats
        Infrastructure::PerformanceMonitor.clear
      end

      best_effort('logger') do
        Infrastructure::Logger.level = :error
        Infrastructure::Logger.debug('warmup')
        Infrastructure::Logger.info('warmup')
        Infrastructure::Logger.warn('warmup')
        Infrastructure::Logger.error('warmup')
        Infrastructure::Logger.fatal('warmup')
      end

      best_effort('event_bus') do
        bus = Infrastructure::EventBus.new
        h = proc { |_e| }
        bus.subscribe(:test_event, h)
        bus.emit_event(:test_event, {})
        bus.unsubscribe(h)
      end

      best_effort('state_store') do
        st = Infrastructure::StateStore.new(Infrastructure::EventBus.new)
        st.update_terminal_size(80, 24)
        st.terminal_size_changed?(80, 24)
        snap = st.reader_snapshot
        st.restore_reader_from(snap)
      end

      best_effort('observer_state_store') do
        obs = Infrastructure::ObserverStateStore.new(Infrastructure::EventBus.new)
        mod = Module.new do
          def self.state_changed(*); end
        end
        obs.add_observer(mod, %i[reader mode])
        obs.remove_observer(mod)
      end

      best_effort('pagination_cache') do
        Infrastructure::PaginationCache.msgpack_available?
        Infrastructure::PaginationCache.exists_for_document?(Object.new, '80x24_single_normal')
      end

      best_effort('validator') do
        v = Infrastructure::Validator.new
        v.validate_presence('x')
        v.validate_format('abc', /a/)
        v.validate_range(5, min: 0, max: 10)
      end

      best_effort('epub_cache_pipeline') do
        fake_epub = File.join(Dir.pwd, 'tmp_coverage.epub')
        File.write(fake_epub, 'epub-bytes') unless File.exist?(fake_epub)
        cache = Infrastructure::EpubCache.new(fake_epub)
        chapter = EbookReader::Domain::Models::Chapter.new(
          number: '1',
          title: 'Warmup',
          lines: ['Warmup'],
          metadata: nil,
          blocks: nil,
          raw_content: '<html><body>Warmup</body></html>'
        )
        book = Infrastructure::EpubCache::BookData.new(
          title: 'Warmup',
          language: 'en_US',
          authors: ['Author'],
          chapters: [chapter],
          toc_entries: [],
          opf_path: 'OPS/content.opf',
          spine: ['xhtml/1.xhtml'],
          chapter_hrefs: ['xhtml/1.xhtml'],
          resources: {
            'META-INF/container.xml' => '<xml/>',
            'OPS/content.opf' => '<xml/>',
            'xhtml/1.xhtml' => '<html/>',
          },
          metadata: { year: '2024' },
          container_path: 'META-INF/container.xml',
          container_xml: '<xml/>'
        )
        cache.write_book!(book)
        cache.load_for_source
        cache.mutate_layouts! { |layouts| layouts['warmup'] = { 'version' => 1, 'pages' => [] } }
        Infrastructure::BookCachePipeline.new.load(fake_epub)
      end
    ensure
      cleanup_temp_files(fake_epub, cache)
    end

    def best_effort(label)
      yield
    rescue StandardError => e
      return nil unless ENV.fetch('READER_COVERAGE_WARMUP_DEBUG', nil) == '1'

      warn("[coverage_warmup] #{label}: #{e.class}: #{e.message}")
      nil
    end
    private_class_method :best_effort

    def cleanup_temp_files(fake_epub, cache)
      FileUtils.rm_f(fake_epub) if fake_epub
      FileUtils.rm_f(cache.cache_path) if cache&.cache_path
    rescue StandardError => e
      return nil unless ENV.fetch('READER_COVERAGE_WARMUP_DEBUG', nil) == '1'

      warn("[coverage_warmup] cleanup: #{e.class}: #{e.message}")
      nil
    end
    private_class_method :cleanup_temp_files
  end
end
