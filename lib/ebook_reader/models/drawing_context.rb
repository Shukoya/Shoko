# frozen_string_literal: true

module EbookReader
  module Models
    # Base context for drawing operations
    DrawingContext = Struct.new(:row, :col, :width, :height, keyword_init: true) do
      def position
        Position.new(row: row, col: col)
      end

      def dimensions
        Dimensions.new(width: width, height: height)
      end
    end

    Position = Struct.new(:row, :col, keyword_init: true)
    Dimensions = Struct.new(:width, :height, keyword_init: true)

    # Specific contexts for different drawing operations
    BookmarkDrawingContext = Struct.new(
      :bookmark, :chapter_title, :index, :position, :width,
      keyword_init: true
    )

    TocDrawingContext = Struct.new(
      :chapter, :index, :position, :width,
      keyword_init: true
    )
  end
end
