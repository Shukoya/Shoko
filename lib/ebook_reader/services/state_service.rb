# frozen_string_literal: true

module EbookReader
  module Services
    # A service that provides methods for managing the reader's state. It includes
    # methods for loading and saving progress, and for applying progress data to
    # the reader.
    class StateService
      def initialize(reader)
        @reader = reader
      end

      def load_progress
        progress = ProgressManager.load(@reader.path)
        return unless progress

        apply_progress_data(progress)
      end

      def save_progress
        return unless valid_save_conditions?

        progress_data = collect_progress_data
        ProgressManager.save(@reader.path, progress_data[:chapter], progress_data[:line_offset])
      end

      private

      def apply_progress_data(progress)
        self.chapter_from_progress = progress
        self.page_offset_from_progress = progress
      end

      def chapter_from_progress=(progress)
        chapter = progress['chapter'] || 0
        @reader.current_chapter = validate_chapter_index(chapter)
      end

      def validate_chapter_index(chapter)
        chapter >= @reader.doc.chapter_count ? 0 : chapter
      end

      def page_offset_from_progress=(progress)
        line_offset = progress['line_offset'] || 0

        if @reader.config.page_numbering_mode == :dynamic && @reader.page_manager
          self.dynamic_page_offset = line_offset
        else
          @reader.send(:page_offsets=, line_offset)
        end
      end

      def dynamic_page_offset=(line_offset)
        height, width = Terminal.size
        @reader.page_manager.build_page_map(width, height)
        @reader.current_page_index = @reader.page_manager.find_page_index(
          @reader.current_chapter, line_offset
        )
      end

      def valid_save_conditions?
        @reader.path && @reader.doc
      end

      def collect_progress_data
        if @reader.config.page_numbering_mode == :dynamic && @reader.page_manager
          collect_dynamic_progress
        else
          collect_absolute_progress
        end
      end

      def collect_dynamic_progress
        page_data = @reader.page_manager.get_page(@reader.current_page_index)
        return { chapter: 0, line_offset: 0 } unless page_data

        {
          chapter: page_data[:chapter_index],
          line_offset: page_data[:start_line],
        }
      end

      def collect_absolute_progress
        line_offset = @reader.config.view_mode == :split ? @reader.left_page : @reader.single_page

        {
          chapter: @reader.current_chapter,
          line_offset: line_offset,
        }
      end
    end
  end
end
