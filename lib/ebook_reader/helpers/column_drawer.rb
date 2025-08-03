# frozen_string_literal: true

module EbookReader
  module Helpers
    module ColumnDrawer
      def draw_left_column(wrapped, col_width, content_height)
        params = build_column_params(
          row: 3, col: 1,
          width: col_width, height: content_height,
          lines: wrapped, offset: @left_page, show_page_num: true
        )
        draw_column(params)
      end

      def draw_right_column(wrapped, col_width, content_height)
        params = build_column_params(
          row: 3, col: col_width + 5,
          width: col_width, height: content_height,
          lines: wrapped, offset: @right_page, show_page_num: false
        )
        draw_column(params)
      end

      private

      def build_column_params(row:, col:, width:, height:, lines:, offset:, show_page_num:)
        Models::ColumnDrawingParams.new(
          position: Models::ColumnDrawingParams::Position.new(row: row, col: col),
          dimensions: Models::ColumnDrawingParams::Dimensions.new(width: width, height: height),
          content: Models::ColumnDrawingParams::Content.new(
            lines: lines, offset: offset, show_page_num: show_page_num
          )
        )
      end
    end
  end
end
