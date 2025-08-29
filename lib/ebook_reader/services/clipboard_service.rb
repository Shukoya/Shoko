# frozen_string_literal: true

module EbookReader
  module Services
    # TEMPORARY: Compatibility wrapper for Services::ClipboardService
    # This delegates to the domain service until all references are migrated
    class ClipboardService
      # Error raised when clipboard operations fail
      class ClipboardError < Domain::Services::ClipboardService::ClipboardError; end

      def self.copy(text)
        container = Domain::ContainerFactory.create_default_container
        clipboard_service = container.resolve(:clipboard_service)
        clipboard_service.copy(text)
      end

      def self.copy_with_feedback(text, &block)
        container = Domain::ContainerFactory.create_default_container
        clipboard_service = container.resolve(:clipboard_service)
        clipboard_service.copy_with_feedback(text, &block)
      end

      def self.available?
        container = Domain::ContainerFactory.create_default_container
        clipboard_service = container.resolve(:clipboard_service)
        clipboard_service.available?
      end
    end
  end
end