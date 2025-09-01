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
        @state.update({[:reader, :bookmarks] => BookmarkManager.get(@path)})
      end

      def add_bookmark
        # Basic bookmark functionality - store current position
        bookmark_data = {
          chapter: @state.get([:reader, :current_chapter]),
          page: @state.get([:reader, :current_page_index]),
          timestamp: Time.now,
        }

        # Add to bookmarks list in state
        current_bookmarks = @state.get([:reader, :bookmarks]) || []
        current_bookmarks << bookmark_data
        @state.update({[:reader, :bookmarks] => current_bookmarks})

        set_message("Bookmark added at Chapter #{@state.get([:reader, :current_chapter]) + 1}, Page #{@state.get([:reader, :current_page])}")
      end

      def jump_to_bookmark
        bookmarks = @state.get([:reader, :bookmarks])
        bookmark = bookmarks[@state.get([:reader, :bookmark_selected])]
        return unless bookmark

        @state.update({
          [:reader, :current_chapter] => bookmark.chapter_index,
          [:reader, :single_page] => bookmark.line_offset,
          [:reader, :left_page] => bookmark.line_offset
        })
        save_progress
        @state.update({[:reader, :mode] => :read})
      end

      def delete_selected_bookmark
        bookmarks = @state.get([:reader, :bookmarks])
        bookmark = bookmarks[@state.get([:reader, :bookmark_selected])]
        return unless bookmark

        BookmarkManager.delete(@path, bookmark)
        load_bookmarks
        if @state.get([:reader, :bookmarks]).any?
          max_selected = [@state.get([:reader, :bookmark_selected]), @state.get([:reader, :bookmarks]).length - 1].min
          @state.update({[:reader, :bookmark_selected] => max_selected})
        end
        set_message(Constants::Messages::BOOKMARK_DELETED)
      end

      def refresh_annotations
        annotations = Annotations::AnnotationStore.get(@path)
        @state.update({[:reader, :annotations] => annotations})
      end

      def quit_to_menu
        save_progress
        @state.update({[:reader, :running] => false})
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
        page_data = page_calculator.get_page(@state.get([:reader, :current_page_index]))
        return { chapter: 0, line_offset: 0 } unless page_data

        {
          chapter: page_data[:chapter_index],
          line_offset: page_data[:start_line],
        }
      end

      def collect_absolute_progress
        line_offset = Domain::Selectors::ConfigSelectors.view_mode(@state) == :split ? 
                        @state.get([:reader, :left_page]) : @state.get([:reader, :single_page])

        {
          chapter: @state.get([:reader, :current_chapter]),
          line_offset: line_offset,
        }
      end

      def apply_progress_data(progress)
        # Set chapter (with validation)
        chapter = progress['chapter'] || 0
        @state.update({[:reader, :current_chapter] => chapter >= @doc.chapter_count ? 0 : chapter})

        # Set page offset
        line_offset = progress['line_offset'] || 0
        page_calculator = @dependencies.resolve(:page_calculator)

        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && page_calculator
          # Dynamic page mode
          height, width = @terminal_service.size
          page_calculator.build_page_map(width, height, @doc, @state)
          page_index = page_calculator.find_page_index(@state.get([:reader, :current_chapter]), line_offset)
          @state.update({[:reader, :current_page_index] => page_index})
        else
          # Absolute page mode
          page_offsets = line_offset
          @state.update({
            [:reader, :single_page] => page_offsets,
            [:reader, :left_page] => page_offsets
          })
        end
      end

      def set_message(text, duration = 2)
        @state.update({[:reader, :message] => text})
        Thread.new do
          sleep duration
          @state.update({[:reader, :message] => nil})
        end
      end
    end
  end
end
