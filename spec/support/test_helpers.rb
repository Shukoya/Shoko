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
      container.register(:state_store, EbookReader::Infrastructure::StateStore.new)
      container.register(:event_bus, EbookReader::Infrastructure::EventBus.new)
    end
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
