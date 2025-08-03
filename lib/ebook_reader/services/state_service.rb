# frozen_string_literal: true

module EbookReader
  module Services
    class StateService
      def initialize(reader)
        @reader = reader
      end

      def load_progress
        progress = ProgressManager.load(@reader.path)
        return unless progress

        apply_progress_data(progress)
      end

      private

      def apply_progress_data(progress)
        set_chapter_from_progress(progress)
        set_page_offset_from_progress(progress)
      end

      def set_chapter_from_progress(progress)
        chapter = progress['chapter'] || 0
        @reader.current_chapter = validate_chapter_index(chapter)
      end

      def validate_chapter_index(chapter)
        chapter >= @reader.doc.chapter_count ? 0 : chapter
      end

      def set_page_offset_from_progress(progress)
        line_offset = progress['line_offset'] || 0

        if @reader.config.page_numbering_mode == :dynamic && @reader.page_manager
          set_dynamic_page_offset(line_offset)
        else
          @reader.send(:page_offsets=, line_offset)
        end
      end

      def set_dynamic_page_offset(line_offset)
        height, width = Terminal.size
        @reader.page_manager.build_page_map(width, height)
        @reader.current_page_index = @reader.page_manager.find_page_index(
          @reader.current_chapter, line_offset
        )
      end

      def save_progress
        return unless valid_save_conditions?

        progress_data = collect_progress_data
        ProgressManager.save(@reader.path, progress_data[:chapter], progress_data[:line_offset])
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
