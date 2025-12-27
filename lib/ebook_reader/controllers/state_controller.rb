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
        # Prefer repositories via DI
        has_resolve = @dependencies.respond_to?(:resolve)
        @progress_repository = @dependencies.resolve(:progress_repository) if has_resolve
        return unless has_resolve

        @bookmark_repository = @dependencies.resolve(:bookmark_repository)
      end

      def save_progress
        return unless @path && @doc

        progress_data = collect_progress_data
        canonical = canonical_path_for_doc

        @progress_repository.save_for_book(canonical,
                                           chapter_index: progress_data[:chapter],
                                           line_offset: progress_data[:line_offset])
      end

      def load_progress
        canonical = canonical_path_for_doc
        progress = @progress_repository.find_by_book_path(canonical)
        # Fallback: attempt original open path if canonical not found (for legacy records)
        progress = @progress_repository.find_by_book_path(@path) if !progress && @path != canonical
        return unless progress

        apply_progress_data(progress)
      end

      def load_bookmarks
        canonical = canonical_path_for_doc
        bookmarks = @bookmark_repository.find_by_book_path(canonical)
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(bookmarks))
      end

      def add_bookmark
        # Basic bookmark functionality - store current position
        current_chapter = @state.get(%i[reader current_chapter])
        current_page_index = @state.get(%i[reader current_page_index])
        bookmark_data = { chapter: current_chapter, page: current_page_index, timestamp: Time.now }

        # Persist and refresh list
        canonical = canonical_path_for_doc
        view_mode = Domain::Selectors::ConfigSelectors.view_mode(@state)
        line_offset = view_mode == :split ? @state.get(%i[reader left_page]) : @state.get(%i[reader single_page])
        text_snippet = ''
        begin
          @bookmark_repository.add_for_book(canonical,
                                            chapter_index: bookmark_data[:chapter],
                                            line_offset: line_offset,
                                            text_snippet: text_snippet)
          bookmarks = @bookmark_repository.find_by_book_path(canonical)
        rescue StandardError
          bookmarks = @state.get(%i[reader bookmarks]) || []
        end
        @state.dispatch(EbookReader::Domain::Actions::UpdateBookmarksAction.new(bookmarks))

        curr_ch = current_chapter
        curr_page = @state.get(%i[reader current_page])
        set_message("Bookmark added at Chapter #{curr_ch + 1}, Page #{curr_page}")
      end

      def jump_to_bookmark
        bookmarks = bookmarks_list
        selected_idx = @state.get(%i[reader bookmark_selected])
        bookmark = bookmarks[selected_idx]
        return unless bookmark

        has_resolve = @dependencies.respond_to?(:resolve)
        navigation = if has_resolve && @dependencies.registered?(:navigation_service)
                       @dependencies.resolve(:navigation_service)
                     end

        chapter_index = bookmark.chapter_index
        if navigation
          navigation.jump_to_chapter(chapter_index)
        else
          @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(chapter_index))
        end

        offset = bookmark.line_offset.to_i
        payload = {
          single_page: offset,
          left_page: offset,
          right_page: offset + 1,
          current_page: offset,
        }

        if EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic &&
           has_resolve && @dependencies.registered?(:page_calculator)
          page_index = @dependencies.resolve(:page_calculator)&.find_page_index(chapter_index,
                                                                                offset)
          payload[:current_page_index] = page_index if page_index
        end

        @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(payload))
        save_progress
        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
      end

      def delete_selected_bookmark
        bookmarks = bookmarks_list
        selected_idx = @state.get(%i[reader bookmark_selected])
        bookmark = bookmarks[selected_idx]
        return unless bookmark

        canonical = canonical_path_for_doc
        @bookmark_repository.delete_for_book(canonical, bookmark)
        load_bookmarks
        current_bookmarks = bookmarks_list
        if current_bookmarks.any?
          max_selected = [selected_idx, current_bookmarks.length - 1].min
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

      def jump_to_annotation(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        chapter_index = normalized[:chapter_index]
        range = normalized[:range]
        navigation = if @dependencies.respond_to?(:resolve) && @dependencies.registered?(:navigation_service)
                       @dependencies.resolve(:navigation_service)
                     end
        navigation&.jump_to_chapter(chapter_index) if chapter_index

        if range
          selection = normalize_selection_for_state(range)
          @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionAction.new(selection)) if selection
        end

        @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
      end

      def delete_annotation_by_id(annotation)
        current_index = @state.get(%i[reader sidebar_annotations_selected]) || 0
        normalized = normalize_annotation(annotation)
        annotation_id = normalized[:id]

        svc = if @dependencies.respond_to?(:resolve) && @dependencies.registered?(:annotation_service)
                @dependencies.resolve(:annotation_service)
              end
        return current_index unless svc && annotation_id

        svc.delete(@path, annotation_id)
        annotations = svc.list_for_book(@path)
        @state.dispatch(EbookReader::Domain::Actions::UpdateAnnotationsAction.new(annotations))

        new_index = [current_index, annotations.length - 1].min
        new_index = 0 if new_index.negative?
        @state.dispatch(EbookReader::Domain::Actions::UpdateSidebarAction.new(
                          annotations_selected: new_index,
                          sidebar_annotations_selected: new_index
                        ))
        new_index
      rescue StandardError
        current_index
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

      def canonical_path_for_doc
        @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
      end

      def normalize_selection_for_state(range)
        return nil unless range

        return range if anchor_range?(range)

        coord = resolve_coordinate_service
        return nil unless coord

        rendered = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(@state)
        coord.normalize_selection_range(range, rendered)
      rescue StandardError
        nil
      end

      def anchor_range?(range)
        return false unless range.is_a?(Hash)

        start_anchor = range[:start] || range['start']
        start_anchor.is_a?(Hash) && (start_anchor.key?(:geometry_key) || start_anchor.key?('geometry_key'))
      end

      def resolve_coordinate_service
        return nil unless @dependencies.respond_to?(:resolve)

        @dependencies.resolve(:coordinate_service)
      rescue StandardError
        nil
      end

      def bookmarks_list
        @state.get(%i[reader bookmarks])
      end

      def collect_progress_data
        page_calculator = @dependencies.resolve(:page_calculator)
        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && page_calculator
          collect_dynamic_progress(page_calculator)
        else
          collect_absolute_progress
        end
      end

      def normalize_annotation(annotation)
        return {} unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
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
            _, content_height = layout.calculate_metrics(width, height,
                                                         Domain::Selectors::ConfigSelectors.view_mode(@state))
            lines_per_page = layout.adjust_for_line_spacing(content_height,
                                                            Domain::Selectors::ConfigSelectors.line_spacing(@state))
            est_index = lines_per_page.positive? ? (line_offset.to_f / lines_per_page).floor : 0
            @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: est_index))
          rescue StandardError
            # best-effort; leave index as-is if estimation fails
          end
          # Store pending precise restore to be applied after background map build
          @state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(
                            pending_progress: {
                              chapter_index: @state.get(%i[reader current_chapter]),
                              line_offset: line_offset,
                            }
                          ))
        else
          # Absolute page mode
          page_offsets = line_offset
          @state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(single_page: page_offsets,
                                                                             left_page: page_offsets))
        end
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        @state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))
      end
    end
  end
end
