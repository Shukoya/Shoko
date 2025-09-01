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
        # Pass dependencies to MouseableReader
        MouseableReader.new(@epub_path, nil, @dependencies).run
      end

      def menu_mode
        # Pass dependencies to MainMenu
        MainMenu.new(@dependencies).run
      end
    end
  end
end
