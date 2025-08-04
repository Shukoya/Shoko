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

      def error_document_for(error_msg)
        doc = Object.new
        define_error_doc_methods(doc, error_msg)
        doc
      end

      private

      def define_error_doc_methods(doc, error_msg)
        doc.define_singleton_method(:title) { 'Error Loading EPUB' }
        doc.define_singleton_method(:language) { 'en_US' }
        doc.define_singleton_method(:chapter_count) { 1 }
        doc.define_singleton_method(:chapters) { [{ title: 'Error', lines: [] }] }
        doc.define_singleton_method(:get_chapter) do |_idx|
          { number: '1', title: 'Error', lines: error_lines(error_msg) }
        end
      end

      def error_lines(error_msg)
        ERROR_MESSAGE_LINES.map { |line| line == '%<error>s' ? error_msg : line }
      end
    end
  end
end
