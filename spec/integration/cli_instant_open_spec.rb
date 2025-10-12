# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CLI instant open pagination orchestration' do
  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state_store) { EbookReader::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:page_calculator) do
    instance_double('PageCalculatorService',
                    build_dynamic_map!: nil,
                    build_absolute_map!: nil,
                    apply_pending_precise_restore!: nil,
                    get_page: { start_line: 0 },
                    total_pages: 1)
  end
  let(:layout_service) do
    instance_double('LayoutService',
                    calculate_metrics: [0, 0],
                    adjust_for_line_spacing: 20)
  end
  let(:terminal_service) do
    instance_double('TerminalService',
                    setup: nil,
                    cleanup: nil,
                    size: [24, 80],
                    start_frame: nil,
                    end_frame: nil,
                    create_surface: instance_double('Surface').as_null_object,
                    read_keys_blocking: [],
                    enable_mouse: nil,
                    disable_mouse: nil,
                    force_cleanup: nil)
  end
  let(:wrapping_service) { instance_double('WrappingService', clear_cache_for_width: nil) }
  let(:background_worker) { instance_double('BackgroundWorker', submit: true, shutdown: nil) }
  let(:coordinate_service) do
    instance_double('CoordinateService',
                    normalize_selection_range: nil,
                    mouse_to_terminal: { x: 0, y: 0 },
                    anchor_from_point: nil)
  end
  let(:annotation_service) { instance_double('AnnotationService', list_for_book: []) }
  let(:selection_service) { instance_double('SelectionService', normalize_range: nil, extract_from_state: nil) }
  let(:bookmark_repository) do
    instance_double('BookmarkRepository',
                    find_by_book_path: [],
                    add_for_book: nil,
                    delete_for_book: nil)
  end
  let(:progress_repository) do
    instance_double('ProgressRepository',
                    save_for_book: nil,
                    find_by_book_path: nil)
  end
  let(:annotation_repository) do
    instance_double('AnnotationRepository',
                    list_for_book: [],
                    delete: nil,
                    add: nil)
  end
  let(:notification_service) do
    instance_double('NotificationService',
                    set_message: nil,
                    tick: nil)
  end
  let(:document) do
    instance_double('EPUBDocument',
                    cached?: false,
                    canonical_path: '/tmp/book.epub',
                    chapter_count: 1,
                    toc_entries: [],
                    chapters: [])
  end
  let(:document_service) { instance_double('DocumentService', load_document: document) }
  let(:container) do
    EbookReader::Domain::DependencyContainer.new.tap do |c|
      c.register(:event_bus, event_bus)
      c.register(:domain_event_bus, EbookReader::Domain::Events::DomainEventBus.new(event_bus))
      c.register(:global_state, state_store)
      c.register(:state_store, state_store)
      c.register(:page_calculator, page_calculator)
      c.register(:layout_service, layout_service)
      c.register(:clipboard_service, double('ClipboardService').as_null_object)
      c.register(:terminal_service, terminal_service)
      c.register(:wrapping_service, wrapping_service)
      c.register(:notification_service, notification_service)
      c.register(:coordinate_service, coordinate_service)
      c.register(:annotation_service, annotation_service)
      c.register(:bookmark_repository, bookmark_repository)
      c.register(:progress_repository, progress_repository)
      c.register(:annotation_repository, annotation_repository)
      c.register(:navigation_service, double('NavigationService').as_null_object)
      c.register(:selection_service, selection_service)
      c.register(:settings_service, double('SettingsService').as_null_object)
      c.register(:library_service, double('LibraryService').as_null_object)
      c.register(:catalog_service, double('CatalogService').as_null_object)
      c.register(:document_service_factory, ->(_path) { document_service })
      c.register(:background_worker, background_worker)
    end
  end

  before do
    allow_any_instance_of(EbookReader::ReaderController).to receive(:build_component_layout)
    allow_any_instance_of(EbookReader::ReaderController).to receive(:apply_theme_palette)
    allow_any_instance_of(EbookReader::ReaderController).to receive(:draw_screen)
    allow_any_instance_of(EbookReader::ReaderController).to receive(:reset_navigable_toc_cache!)
  end

  it 'delegates initial pagination to the shared orchestrator' do
    cache_payload = { key: '80x24-split-compact', map: [1], total: 1 }
    orchestrator = instance_double('PaginationOrchestrator',
                                   initial_build: { page_map_cache: cache_payload },
                                   refresh_after_resize: nil,
                                   build_full_map!: nil,
                                   rebuild_dynamic: nil)
    allow(EbookReader::Application::PaginationOrchestrator).to receive(:new).and_return(orchestrator)

    controller = EbookReader::ReaderController.new('/tmp/book.epub', nil, container)
    controller.send(:perform_initial_calculations_with_progress)

    expect(orchestrator).to have_received(:initial_build).with(document, state_store, page_calculator)
    expect(controller.instance_variable_get(:@page_map_cache)).to eq(cache_payload)
  end
end
