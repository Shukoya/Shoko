# frozen_string_literal: true

module EbookReader
  module Application
    # Builds ReaderViewModel from state and document, keeping controller lean.
    class ReaderViewModelBuilder
      def initialize(state, doc)
        @state = state
        @doc = doc
      end

      def build(page_info)
        ch = @state.get(%i[reader current_chapter])
        toc_entries = if @doc.respond_to?(:toc_entries)
                        @doc.toc_entries
                      else
                        []
                      end

        UI::ViewModels::ReaderViewModel.new(
          current_chapter: ch,
          total_chapters: @doc&.chapters&.length || 0,
          current_page: @state.get(%i[reader current_page]),
          total_pages: @state.get(%i[reader total_pages]),
          chapter_title: @doc&.get_chapter(ch)&.title || '',
          document_title: @doc&.title || '',
          view_mode: @state.get(%i[config view_mode]) || :split,
          sidebar_visible: @state.get(%i[reader sidebar_visible]),
          mode: @state.get(%i[reader mode]),
          message: @state.get(%i[reader message]),
          bookmarks: @state.get(%i[reader bookmarks]) || [],
          toc_entries: toc_entries,
          show_page_numbers: @state.get(%i[config show_page_numbers]) || true,
          page_numbering_mode: @state.get(%i[config page_numbering_mode]) || :absolute,
          line_spacing: @state.get(%i[config line_spacing]) || EbookReader::Constants::DEFAULT_LINE_SPACING,
          language: @doc&.language || 'en',
          page_info: page_info
        )
      end
    end
  end
end
