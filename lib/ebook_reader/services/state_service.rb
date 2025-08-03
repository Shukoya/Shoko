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

        @reader.current_chapter = progress['chapter'] || 0
        line_offset = progress['line_offset'] || 0
        @reader.current_chapter = 0 if @reader.current_chapter >= @reader.doc.chapter_count

        if @reader.config.page_numbering_mode == :dynamic && @reader.page_manager
          height, width = Terminal.size
          @reader.page_manager.build_page_map(width, height)
          @reader.current_page_index = @reader.page_manager.find_page_index(
            @reader.current_chapter, line_offset
          )
        else
          @reader.send(:page_offsets=, line_offset)
        end
      end

      def save_progress
        return unless @reader.path && @reader.doc

        if @reader.config.page_numbering_mode == :dynamic && @reader.page_manager
          page_data = @reader.page_manager.get_page(@reader.current_page_index)
          if page_data
            ProgressManager.save(@reader.path, page_data[:chapter_index],
                                 page_data[:start_line])
          end
        else
          line_offset = @reader.config.view_mode == :split ? @reader.left_page : @reader.single_page
          ProgressManager.save(@reader.path, @reader.current_chapter, line_offset)
        end
      end
    end
  end
end
