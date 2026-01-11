# frozen_string_literal: true

module Shoko
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      def initialize(epub_path = nil)
        @epub_path = epub_path
        @dependencies = Shoko::Application::ContainerFactory.create_default_container
        @instrumentation = begin
          @dependencies.resolve(:instrumentation_service)
        rescue StandardError
          nil
        end
      end

      def run
        if @epub_path
          reader_mode
        else
          menu_mode
        end
      end

      private

      def reader_mode
        # Ensure alternate screen is entered before any heavy work for instant-open UX
        term = @dependencies.resolve(:terminal_service)
        term.setup
        @instrumentation&.start_trace(@epub_path)
        begin
          # Pass dependencies to MouseableReader
          Controllers::MouseableReader.new(@epub_path, nil, @dependencies).run
        ensure
          # Balance setup to avoid lingering session depth
          term.cleanup
          @instrumentation&.cancel_trace
        end
      end

      def menu_mode
        # Pass dependencies to MenuController
        Controllers::MenuController.new(@dependencies).run
      end
    end
  end
end
