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
        # Prefer repositories via DI; fall back to legacy managers for compatibility in tests
        @progress_repository = @dependencies.resolve(:progress_repository) if @dependencies.respond_to?(:resolve)
        @bookmark_repository = @dependencies.resolve(:bookmark_repository) if @dependencies.respond_to?(:resolve)
      end

      def save_progress
        return unless @path && @doc

        progress_data = collect_progress_data
        canonical = @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path

        if @progress_repository
          @progress_repository.save_for_book(canonical,
                                             chapter_index: progress_data[:chapter],
                                             line_offset: progress_data[:line_offset])
        else
          ProgressManager.save(canonical, progress_data[:chapter], progress_data[:line_offset])
        end
      end

      def load_progress
        canonical = @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
        progress = if @progress_repository
                     @progress_repository.find_by_book_path(canonical)
                   else
                     ProgressManager.load(canonical)
                   end
        # Fallback: attempt original open path if canonical not found (for legacy records)
        if !progress && @path != canonical
          progress = if @progress_repository
                       @progress_repository.find_by_book_path(@path)
                     else
                       ProgressManager.load(@path)
                     end
        end
        return unless progress

        apply_progress_data(progress)
      end

      def load_bookmarks
        canonical = @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
        bookmarks = if @bookmark_repository
                      @bookmark_repository.find_by_book_path(canonical)
                    else
                      BookmarkManager.get(canonical)
                    end
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(bookmarks))
      end

      def add_bookmark
        # Basic bookmark functionality - store current position
        bookmark_data = {
          chapter: @state.get(%i[reader current_chapter]),
          page: @state.get(%i[reader current_page_index]),
          timestamp: Time.now,
        }

        # Persist and refresh list
        canonical = @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
        line_offset = if Domain::Selectors::ConfigSelectors.view_mode(@state) == :split
                        @state.get(%i[reader left_page])
                      else
                        @state.get(%i[reader single_page])
                      end
        text_snippet = ''
        begin
          if @bookmark_repository
            @bookmark_repository.add_for_book(canonical,
                                              chapter_index: bookmark_data[:chapter],
                                              line_offset: line_offset,
                                              text_snippet: text_snippet)
            bookmarks = @bookmark_repository.find_by_book_path(canonical)
          else
            bm = EbookReader::Domain::Models::BookmarkData.new(path: canonical,
                                                               chapter: bookmark_data[:chapter],
                                                               line_offset: line_offset,
                                                               text: text_snippet)
            BookmarkManager.add(bm)
            bookmarks = BookmarkManager.get(canonical)
          end
        rescue StandardError
          bookmarks = @state.get(%i[reader bookmarks]) || []
        end
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(bookmarks))

        set_message("Bookmark added at Chapter #{@state.get(%i[reader
                                                               current_chapter]) + 1}, Page #{@state.get(%i[
                                                                                                           reader current_page
                                                                                                         ])}")
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

        canonical = @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
        if @bookmark_repository
          @bookmark_repository.delete_for_book(canonical, bookmark)
        else
          BookmarkManager.delete(canonical, bookmark)
        end
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
          annotations = svc ? svc.list_for_book(@path) : []
        rescue StandardError => e
          # Log the error and keep annotations empty
          begin
            @dependencies.resolve(:logger).error('Failed to refresh annotations', error: e.message,
                                                                                path: @path)
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
        chapter = if progress.respond_to?(:chapter_index)
                    progress.chapter_index
                  else
                    progress['chapter'] || progress[:chapter] || 0
                  end
        @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(chapter >= @doc.chapter_count ? 0 : chapter))

        # Set page offset
        line_offset = if progress.respond_to?(:line_offset)
                        progress.line_offset
                      else
                        progress['line_offset'] || progress[:line_offset] || 0
                      end
        page_calculator = @dependencies.resolve(:page_calculator)

        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && page_calculator
          # Dynamic page mode (lazy): estimate index now; compute precisely after background build
          begin
            # Use state-known terminal dimensions to avoid relying on TerminalService setup timing
            width  = (@state.get(%i[ui terminal_width]) || 80).to_i
            height = (@state.get(%i[ui terminal_height]) || 24).to_i
            layout = @dependencies.resolve(:layout_service)
            col_width, content_height = layout.calculate_metrics(width, height,
                                                                 Domain::Selectors::ConfigSelectors.view_mode(@state))
            lines_per_page = layout.adjust_for_line_spacing(content_height,
                                                            Domain::Selectors::ConfigSelectors.line_spacing(@state))
            est_index = lines_per_page.positive? ? (line_offset.to_f / lines_per_page).floor : 0
            @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: est_index))
          rescue StandardError
            # best-effort; leave index as-is if estimation fails
          end
          # Store pending precise restore to be applied after background map build
          @state.update({ %i[reader pending_progress] => {
                           chapter_index: @state.get(%i[reader current_chapter]),
                           line_offset: line_offset,
                         } })
        else
          # Absolute page mode
          page_offsets = line_offset
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(single_page: page_offsets,
                                                                             left_page: page_offsets))
        end
      end

      def set_message(text, duration = 2)
        begin
          notifier = @dependencies.resolve(:notification_service)
          notifier.set_message(@state, text, duration)
        rescue StandardError
          @state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))
        end
      end
    end
  end
end
