# frozen_string_literal: true

module EbookReader
  module Models
    # Parameter object to reduce long parameter lists in renderers.
    class RenderParams
      attr_reader :start_row, :col_start, :col_width, :context

      def initialize(start_row:, col_start:, col_width:, context: nil)
        @start_row = start_row
        @col_start = col_start
        @col_width = col_width
        @context = context
      end
    end
  end
end
