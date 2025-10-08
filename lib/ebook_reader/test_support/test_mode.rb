# frozen_string_literal: true

require_relative 'terminal_double'

module EbookReader
  module TestSupport
    # Central hook that enables deterministic test behaviour by swapping in
    # lightweight adapters and updating the dependency container.
    module TestMode
      module_function

      def active?
        ENV.fetch('EBOOK_READER_TEST_MODE', nil) == '1'
      end

      def activate!
        return unless active?

        install_terminal_double!
        silence_logger!
      end

      def configure_container(container)
        return unless active?

        container.register_singleton(:terminal_service) do |c|
          TestTerminalService.new(c)
        end
      end

      # Test-specialised terminal service that exposes helpers for enqueuing
      # deterministic input sequences while delegating behaviour to the base
      # implementation (now backed by the TerminalDouble).
      class TestTerminalService < EbookReader::Domain::Services::TerminalService
        def queue_input(*keys)
          EbookReader::TestSupport::TerminalDouble.push_input(*keys)
        end

        def drain_input
          EbookReader::TestSupport::TerminalDouble.drain_input
        end

        def configure_size(height:, width:)
          EbookReader::TestSupport::TerminalDouble.size = [height, width]
        end
      end

      def install_terminal_double!
        return if @terminal_installed
        real_terminal = if EbookReader.const_defined?(:Terminal, false)
                          EbookReader.const_get(:Terminal)
                        end
        EbookReader.const_set(:RealTerminal, real_terminal) unless EbookReader.const_defined?(:RealTerminal)
        EbookReader.send(:remove_const, :Terminal) if EbookReader.const_defined?(:Terminal, false)
        EbookReader.const_set(:Terminal, EbookReader::TestSupport::TerminalDouble)
        EbookReader::TestSupport::TerminalDouble.reset!
        @terminal_installed = true
      end

      def silence_logger!
        return unless defined?(EbookReader::Infrastructure::Logger)

        begin
          EbookReader::Infrastructure::Logger.output = logger_null_io
          EbookReader::Infrastructure::Logger.level = :fatal
        rescue StandardError
          nil
        end
      end

      def logger_null_io
        @null_logger_io ||= File.open(File::NULL, 'w')
      rescue StandardError
        nil
      end
    end
  end
end
