# frozen_string_literal: true

module EbookReader
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      def initialize(epub_path = nil)
        @epub_path = epub_path
        @dependencies = Domain::ContainerFactory.create_default_container
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
        # Use original MouseableReader to ensure books open correctly
        # ReaderApplication will be used after Phase 1 completion
        MouseableReader.new(@epub_path).run
      end

      def menu_mode
        # Keep original menu appearance - DO NOT CHANGE UI
        MainMenu.new.run
      end
    end
  end
end
