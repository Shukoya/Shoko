# frozen_string_literal: true

module EbookReader
  module Models
    # Context object for rendering operations.
    # Replaces direct controller dependency in renderers with structured data access.
    class RenderingContext
      attr_reader :document, :page_manager, :state, :config, :view_model

      def initialize(document:, state:, config:, view_model:, page_manager: nil)
        @document = document
        @page_manager = page_manager
        @state = state
        @config = config
        @view_model = view_model
        freeze
      end

      # Convenience methods for common rendering needs
      def current_chapter
        @document&.get_chapter(@state.get([:reader, :current_chapter]))
      end

      def current_page_index
        @state.get([:reader, :current_page_index])
      end

      def view_mode
        EbookReader::Domain::Selectors::ConfigSelectors.view_mode(@state)
      end

      def page_numbering_mode
        EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(@state)
      end

      # Dynamic mode page data access
      def get_page_data(index)
        return nil unless @page_manager && page_numbering_mode == :dynamic

        @page_manager.get_page(index)
      end

      def total_pages
        if @page_manager && page_numbering_mode == :dynamic
          @page_manager.total_pages
        else
          @state.get([:reader, :total_pages])
        end
      end
    end
  end
end
