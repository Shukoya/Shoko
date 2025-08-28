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
    allow(EbookReader::Terminal).to receive(:size).and_return([height, width])
    allow(EbookReader::Terminal).to receive(:setup)
    allow(EbookReader::Terminal).to receive(:cleanup)
    allow(EbookReader::Terminal).to receive(:start_frame)
    allow(EbookReader::Terminal).to receive(:end_frame)
  end

  def create_test_dependencies
    EbookReader::Domain::DependencyContainer.new.tap do |container|
      container.register(:state_store, EbookReader::Infrastructure::StateStore.new)
      container.register(:event_bus, EbookReader::Infrastructure::EventBus.new)
    end
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
