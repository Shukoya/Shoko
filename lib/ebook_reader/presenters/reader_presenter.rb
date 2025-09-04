# frozen_string_literal: true

module EbookReader
  module Presenters
    # Handles presentation logic for the Reader
    class ReaderPresenter
      attr_reader :reader, :config

      ERROR_MESSAGE_LINES = [
        'Failed to load EPUB file:',
        '',
        '%<error>s',
        '',
        'Possible causes:',
        '- The file might be corrupted',
        '- The file might not be a valid EPUB',
        '- The file might be password protected',
        '',
        "Press 'q' to return to the menu",
      ].freeze
      private_constant :ERROR_MESSAGE_LINES

      def initialize(reader, config)
        @reader = reader
        @config = config
      end

      # Error rendering is handled by Infrastructure::DocumentService::ErrorDocument
      # This presenter no longer fabricates error documents via singleton methods.
      private
      def error_lines(error_msg)
        ERROR_MESSAGE_LINES.map { |line| line == '%<error>s' ? error_msg : line }
      end
    end
  end
end
