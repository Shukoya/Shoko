# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Controllers::Menu::StateController do
  # Lightweight container used to supply the few dependencies StateController resolves
  class StubContainer
    def initialize(registry = {})
      @registry = registry
    end

    def resolve(name)
      entry = @registry[name]
      entry = entry.call(self) if entry.respond_to?(:call)
      entry
    end

    def registered?(name)
      @registry.key?(name)
    end

    def register(name, value)
      @registry[name] = value
    end
  end

  let(:terminal_class) do
    Class.new do
      class << self
        def setup_calls
          @setup_calls ||= 0
        end

        def cleanup_calls
          @cleanup_calls ||= 0
        end

        def reset!
          @setup_calls = 0
          @cleanup_calls = 0
        end

        def setup
          @setup_calls = setup_calls + 1
        end

        def cleanup
          @cleanup_calls = cleanup_calls + 1
        end

        def start_frame; end
        def end_frame; end
        def size
          [24, 80]
        end

        def print(*) end
        def flush(*) end
        def move(*) '' end
      end
    end
  end

  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:catalog) { Struct.new(:scan_message, :scan_status).new }
  let(:registry) do
    {
      progress_repository: instance_double('ProgressRepository', save_for_book: nil, find_by_book_path: nil),
      bookmark_repository: instance_double('BookmarkRepository',
                                           find_by_book_path: [],
                                           add_for_book: nil,
                                           delete_for_book: nil),
      recent_library_repository: instance_double('RecentLibraryRepository', add: nil),
      annotation_service: instance_double('AnnotationService', list_for_book: [], list_all: {}),
      page_calculator: instance_double('PageCalculator', get_page: nil)
    }
  end
  let(:container) { StubContainer.new(registry) }
  let(:terminal_service) { EbookReader::Domain::Services::TerminalService.new(container) }

  let(:menu) do
    Class.new do
      attr_reader :state, :dependencies, :catalog, :terminal_service, :last_mode

      def initialize(state, dependencies, catalog, terminal_service)
        @state = state
        @dependencies = dependencies
        @catalog = catalog
        @terminal_service = terminal_service
        @last_mode = nil
      end

      def switch_to_mode(mode)
        @last_mode = mode
      end
    end.new(state, container, catalog, terminal_service)
  end

  before do
    stub_const('EbookReader::Terminal', terminal_class)
    terminal_class.reset!

    container.register(:terminal_service, terminal_service)
    container.register(:logger, EbookReader::Infrastructure::Logger)
    container.register(:notification_service,
                       EbookReader::Domain::Services::NotificationService.new(container))

    EbookReader::Domain::Services::TerminalService.session_depth = 0

    reader_double = instance_double('MouseableReader')
    allow(reader_double).to receive(:run) do
      terminal_service.setup
      terminal_service.cleanup
    end
    allow(EbookReader::MouseableReader).to receive(:new)
      .and_return(reader_double)
  end

  it 'restores terminal session depth after returning from the reader' do
    state_controller = described_class.new(menu)

    terminal_service.setup
    expect(terminal_class.setup_calls).to eq(1)
    expect(EbookReader::Domain::Services::TerminalService.session_depth).to eq(1)

    state_controller.run_reader('/tmp/fake.epub')

    expect(EbookReader::Domain::Services::TerminalService.session_depth).to eq(1)
    expect(terminal_class.setup_calls).to eq(1)
    expect(terminal_class.cleanup_calls).to eq(0)

    terminal_service.cleanup

    expect(terminal_class.cleanup_calls).to eq(1)
    expect(EbookReader::Domain::Services::TerminalService.session_depth).to eq(0)
  end
end
