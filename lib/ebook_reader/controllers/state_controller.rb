# frozen_string_literal: true

module EbookReader
  module Controllers
    # Handles all state management: persistence, bookmarks, progress
    class StateController
      def initialize(state, doc, path, dependencies)
        @state = state
        @doc = doc
        @path = path
        @dependencies = dependencies
        @terminal_service = @dependencies.resolve(:terminal_service)
      end

      def save_progress
        return unless @path && @doc

        progress_data = collect_progress_data
        ProgressManager.save(@path, progress_data[:chapter], progress_data[:line_offset])
      end

      def load_progress
        progress = ProgressManager.load(@path)
        return unless progress

        apply_progress_data(progress)
      end

      def load_bookmarks
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(BookmarkManager.get(@path)))
      end

      def add_bookmark
        # Basic bookmark functionality - store current position
        bookmark_data = {
          chapter: @state.get(%i[reader current_chapter]),
          page: @state.get(%i[reader current_page_index]),
          timestamp: Time.now,
        }

        # Add to bookmarks list in state
        current_bookmarks = @state.get(%i[reader bookmarks]) || []
        current_bookmarks << bookmark_data
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(current_bookmarks))

        set_message("Bookmark added at Chapter #{@state.get(%i[reader current_chapter]) + 1}, Page #{@state.get(%i[reader current_page])}")
      end

      def jump_to_bookmark
        bookmarks = @state.get(%i[reader bookmarks])
        bookmark = bookmarks[@state.get(%i[reader bookmark_selected])]
        return unless bookmark
        @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(bookmark.chapter_index))
        @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(single_page: bookmark.line_offset,
                                                                           left_page: bookmark.line_offset))
        save_progress
        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
      end

      def delete_selected_bookmark
        bookmarks = @state.get(%i[reader bookmarks])
        bookmark = bookmarks[@state.get(%i[reader bookmark_selected])]
        return unless bookmark

        BookmarkManager.delete(@path, bookmark)
        load_bookmarks
        if @state.get(%i[reader bookmarks]).any?
          max_selected = [@state.get(%i[reader bookmark_selected]),
                          @state.get(%i[reader bookmarks]).length - 1].min
          @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(bookmark_selected: max_selected))
        end
        set_message(Constants::Messages::BOOKMARK_DELETED)
      end

      def refresh_annotations
        annotations = []
        begin
          svc = @dependencies.resolve(:annotation_service) if @dependencies.respond_to?(:resolve)
          if svc
            annotations = svc.list_for_book(@path)
          else
            # Fallback to store for test contexts lacking DI registration
            if defined?(EbookReader::Annotations::AnnotationStore)
              annotations = EbookReader::Annotations::AnnotationStore.get(@path) || []
            end
          end
        rescue StandardError => e
          # Log the error and keep annotations empty
          begin
            @dependencies.resolve(:logger).error('Failed to refresh annotations', error: e.message, path: @path)
          rescue StandardError
            # no-op
          end
        ensure
          @state.dispatch(Domain::Actions::UpdateAnnotationsAction.new(annotations))
        end
      end

      def quit_to_menu
        save_progress
        @state.dispatch(EbookReader::Domain::Actions::QuitToMenuAction.new)
      end

      def quit_application
        save_progress
        @terminal_service.cleanup
        exit 0
      end

      private

      def collect_progress_data
        page_calculator = @dependencies.resolve(:page_calculator)
        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && page_calculator
          collect_dynamic_progress(page_calculator)
        else
          collect_absolute_progress
        end
      end

      def collect_dynamic_progress(page_calculator)
        page_data = page_calculator.get_page(@state.get(%i[reader current_page_index]))
        return { chapter: 0, line_offset: 0 } unless page_data

        {
          chapter: page_data[:chapter_index],
          line_offset: page_data[:start_line],
        }
      end

      def collect_absolute_progress
        line_offset = if Domain::Selectors::ConfigSelectors.view_mode(@state) == :split
                        @state.get(%i[reader left_page])
                      else
                        @state.get(%i[reader single_page])
                      end

        {
          chapter: @state.get(%i[reader current_chapter]),
          line_offset: line_offset,
        }
      end

      def apply_progress_data(progress)
        # Set chapter (with validation)
        chapter = progress['chapter'] || 0
        @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(chapter >= @doc.chapter_count ? 0 : chapter))

        # Set page offset
        line_offset = progress['line_offset'] || 0
        page_calculator = @dependencies.resolve(:page_calculator)

        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && page_calculator
          # Dynamic page mode
          height, width = @terminal_service.size
          page_calculator.build_page_map(width, height, @doc, @state)
          page_index = page_calculator.find_page_index(@state.get(%i[reader current_chapter]),
                                                       line_offset)
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: page_index))
        else
          # Absolute page mode
          page_offsets = line_offset
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(single_page: page_offsets,
                                                                             left_page: page_offsets))
        end
      end

      def set_message(text, duration = 2)
        @state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))
        begin
          @message_timer&.kill if @message_timer&.alive?
        rescue StandardError
          # ignore
        end
        @message_timer = Thread.new do
          sleep duration
          @state.dispatch(EbookReader::Domain::Actions::ClearMessageAction.new)
        end
      end
    end
  end
end
